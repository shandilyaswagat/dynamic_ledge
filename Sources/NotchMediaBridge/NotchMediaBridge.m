#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <math.h>
#include <unistd.h>
#include "NotchMediaBridge.h"

// MediaRemote is private, so every symbol is looked up at runtime and checked.
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);

enum {
    NotchCommandPlay = 0,
    NotchCommandPause = 1,
    NotchCommandToggle = 2,
    NotchCommandNext = 4,
    NotchCommandPrevious = 5,
};

static MRRegisterFn MRRegister;
static MRGetInfoFn MRGetInfo;
static MRGetIsPlayingFn MRGetIsPlaying;
static MRGetPIDFn MRGetPID;
static MRGetClientFn MRGetClient;
static MRSendCommandFn MRSendCommand;
static MRSetElapsedFn MRSetElapsed;

static dispatch_queue_t bridgeQueue;
static NSString *lastSignature;
static NSString *lastArtworkKey;
static BOOL refreshScheduled;
static const NSUInteger MaximumArtworkBytes = 4 * 1024 * 1024;
static const NSUInteger MaximumMetadataLength = 4096;
static const NSUInteger MaximumCommandBytes = 4096;

static void emit(NSDictionary *payload) {
    // NSJSONSerialization throws on NaN or infinity; never let one reach it.
    if (![NSJSONSerialization isValidJSONObject:payload]) {
        return;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (json == nil) {
        return;
    }
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *boundedString(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }
    NSString *string = value;
    return string.length <= MaximumMetadataLength ? string : [string substringToIndex:MaximumMetadataLength];
}

/// Live streams report NaN or infinite lengths; only finite numbers are passed on.
static NSNumber *finiteNumber(id value) {
    if (![value isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    double number = [value doubleValue];
    return isfinite(number) ? value : nil;
}

static NSString *clientBundleIdentifier(id client) {
    if (client == nil) {
        return nil;
    }
    for (NSString *key in @[@"parentApplicationBundleIdentifier", @"bundleIdentifier"]) {
        SEL selector = NSSelectorFromString(key);
        if ([client respondsToSelector:selector]) {
            id value = [client valueForKey:key];
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                return boundedString(value);
            }
        }
    }
    return nil;
}

static void publish(NSDictionary *info, BOOL isPlaying, int pid, NSString *bundleIdentifier) {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"type"] = @"nowPlaying";
    payload[@"hasInfo"] = @(info.count > 0);
    payload[@"playing"] = @(isPlaying);
    payload[@"pid"] = @(pid);
    if (bundleIdentifier != nil) {
        payload[@"bundleID"] = bundleIdentifier;
    }
    payload[@"title"] = boundedString(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
    payload[@"artist"] = boundedString(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
    payload[@"album"] = boundedString(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);

    NSNumber *duration = finiteNumber(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
    NSNumber *elapsed = finiteNumber(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
    NSNumber *rate = finiteNumber(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
    NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if (duration != nil) payload[@"duration"] = duration;
    if (elapsed != nil) payload[@"elapsed"] = elapsed;
    if (rate != nil) payload[@"rate"] = rate;
    if ([timestamp isKindOfClass:[NSDate class]] && isfinite(timestamp.timeIntervalSince1970)) {
        payload[@"timestamp"] = @(timestamp.timeIntervalSince1970);
    }

    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    NSString *artworkKey = nil;
    if ([artwork isKindOfClass:[NSData class]] && artwork.length > 0 && artwork.length <= MaximumArtworkBytes) {
        id identifier = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
        artworkKey = [identifier isKindOfClass:[NSString class]]
            ? boundedString(identifier)
            : [NSString stringWithFormat:@"%lu-%lu", (unsigned long)artwork.length, (unsigned long)artwork.hash];
        payload[@"artworkKey"] = artworkKey;
    }

    if (![NSJSONSerialization isValidJSONObject:payload]) {
        return;
    }
    // Skip duplicates. The signature leaves out artwork bytes, which can be large.
    NSData *signatureData = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingSortedKeys error:nil];
    NSString *signature = [[NSString alloc] initWithData:signatureData encoding:NSUTF8StringEncoding];
    if (signature != nil && [signature isEqualToString:lastSignature]) {
        return;
    }
    lastSignature = signature;

    // Artwork travels only when it changes. The app drops its image whenever a track has
    // none, so forget ours too; otherwise the same art coming back would never be resent.
    if (artworkKey == nil) {
        lastArtworkKey = nil;
    } else if (![artworkKey isEqualToString:lastArtworkKey]) {
        payload[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
        lastArtworkKey = artworkKey;
    }
    emit(payload);
}

static void refreshNow(void) {
    __block NSDictionary *info = nil;
    __block Boolean isPlaying = false;
    __block int pid = 0;
    __block NSString *bundleIdentifier = nil;
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_enter(group);
    MRGetInfo(bridgeQueue, ^(NSDictionary *value) {
        info = value;
        dispatch_group_leave(group);
    });
    if (MRGetIsPlaying != NULL) {
        dispatch_group_enter(group);
        MRGetIsPlaying(bridgeQueue, ^(Boolean value) {
            isPlaying = value;
            dispatch_group_leave(group);
        });
    }
    if (MRGetPID != NULL) {
        dispatch_group_enter(group);
        MRGetPID(bridgeQueue, ^(int value) {
            pid = value;
            dispatch_group_leave(group);
        });
    }
    if (MRGetClient != NULL) {
        dispatch_group_enter(group);
        MRGetClient(bridgeQueue, ^(id client) {
            bundleIdentifier = clientBundleIdentifier(client);
            dispatch_group_leave(group);
        });
    }

    dispatch_group_notify(group, bridgeQueue, ^{
        NSNumber *rate = finiteNumber(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
        BOOL playing = isPlaying || (rate != nil && rate.doubleValue > 0);
        publish(info ?: @{}, playing, pid, bundleIdentifier);
    });
}

// Notifications arrive in bursts; coalesce them into one refresh.
static void scheduleRefresh(void) {
    dispatch_async(bridgeQueue, ^{
        if (refreshScheduled) {
            return;
        }
        refreshScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), bridgeQueue, ^{
            refreshScheduled = NO;
            refreshNow();
        });
    });
}

static void handleCommand(NSString *line) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return;
    }
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@" "];
    NSString *verb = parts.firstObject;
    if ([verb isEqualToString:@"refresh"]) {
        lastSignature = nil;
        lastArtworkKey = nil;
        scheduleRefresh();
        return;
    }
    if ([verb isEqualToString:@"seek"] && parts.count > 1 && MRSetElapsed != NULL) {
        double position = parts[1].doubleValue;
        if (!isfinite(position) || position < 0) {
            return;
        }
        MRSetElapsed(position);
        scheduleRefresh();
        return;
    }
    if (MRSendCommand == NULL) {
        return;
    }
    NSDictionary<NSString *, NSNumber *> *commands = @{
        @"play": @(NotchCommandPlay),
        @"pause": @(NotchCommandPause),
        @"toggle": @(NotchCommandToggle),
        @"next": @(NotchCommandNext),
        @"previous": @(NotchCommandPrevious),
    };
    NSNumber *command = commands[verb];
    if (command != nil) {
        MRSendCommand(command.intValue, nil);
        scheduleRefresh();
    }
}

static void startReadingCommands(void) {
    static NSMutableData *pending;
    pending = [NSMutableData data];
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, bridgeQueue);
    dispatch_source_set_event_handler(source, ^{
        char buffer[1024];
        ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
        if (count <= 0) {
            // The app went away. Never linger as an orphan.
            exit(0);
        }
        [pending appendBytes:buffer length:(NSUInteger)count];
        // Only the app owns this pipe, but a malformed or compromised helper must not be able
        // to make its long-lived command buffer grow without bound.
        if (pending.length > MaximumCommandBytes) {
            [pending setLength:0];
            return;
        }
        while (YES) {
            NSRange newline = [pending rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, pending.length)];
            if (newline.location == NSNotFound) {
                break;
            }
            NSData *lineData = [pending subdataWithRange:NSMakeRange(0, newline.location)];
            [pending replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (line != nil) {
                handleCommand(line);
            }
        }
    });
    dispatch_resume(source);
    // Keep the source alive for the life of the process.
    static dispatch_source_t retained;
    retained = source;
}

static NSString *constantName(void *framework, const char *symbol) {
    NSString *__unsafe_unretained *pointer = (NSString *__unsafe_unretained *)dlsym(framework, symbol);
    return (pointer != NULL && *pointer != nil) ? *pointer : @(symbol);
}

void notch_media_stream(void *interpreter, void *cv) {
    (void)interpreter;
    (void)cv;
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOFBF, 1 << 16);
        void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (framework == NULL) {
            emit(@{@"type": @"error", @"message": @"MediaRemote unavailable"});
            exit(1);
        }
        MRRegister = (MRRegisterFn)dlsym(framework, "MRMediaRemoteRegisterForNowPlayingNotifications");
        MRGetInfo = (MRGetInfoFn)dlsym(framework, "MRMediaRemoteGetNowPlayingInfo");
        MRGetIsPlaying = (MRGetIsPlayingFn)dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        MRGetPID = (MRGetPIDFn)dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationPID");
        MRGetClient = (MRGetClientFn)dlsym(framework, "MRMediaRemoteGetNowPlayingClient");
        MRSendCommand = (MRSendCommandFn)dlsym(framework, "MRMediaRemoteSendCommand");
        MRSetElapsed = (MRSetElapsedFn)dlsym(framework, "MRMediaRemoteSetElapsedTime");
        if (MRGetInfo == NULL || MRRegister == NULL) {
            emit(@{@"type": @"error", @"message": @"MediaRemote symbols missing"});
            exit(1);
        }

        bridgeQueue = dispatch_queue_create("notch.media.bridge", DISPATCH_QUEUE_SERIAL);
        MRRegister(bridgeQueue);

        const char *names[] = {
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
            "kMRMediaRemotePlaybackStateDidChangeNotification",
        };
        for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
            [NSNotificationCenter.defaultCenter addObserverForName:constantName(framework, names[index])
                                                            object:nil
                                                             queue:nil
                                                        usingBlock:^(NSNotification *note) {
                (void)note;
                scheduleRefresh();
            }];
        }

        startReadingCommands();
        emit(@{@"type": @"ready"});
        scheduleRefresh();

        // Safety net for players that forget to post notifications.
        dispatch_source_t poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, bridgeQueue);
        dispatch_source_set_timer(poll, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(poll, ^{
            refreshNow();
        });
        dispatch_resume(poll);
        static dispatch_source_t retainedPoll;
        retainedPoll = poll;
    }
    CFRunLoopRun();
    exit(0);
}
