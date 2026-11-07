// Reads and controls "Now Playing" for Island's player.
//
// macOS 15.4 and later answer the private MediaRemote calls only for Apple-signed processes, so Island cannot make them
// itself. This library is loaded into /usr/bin/perl (an Apple-signed program, started by Island) which can. Two entry
// points, each called by perl the way it calls an XS function (the arguments are ignored):
//   adapter_stream  prints one line of JSON about what is playing, every second while something plays and every three
//                   seconds while nothing does, until its parent exits.
//   adapter_send    sends the play-back command whose number is in the ISLAND_MR_COMMAND environment variable.
//   adapter_seek    moves the playing position to the number of seconds in the ISLAND_MR_SEEK environment variable.
// Built by scripts/build-app.sh into Island.app/Contents/Resources/NowPlayingAdapter.dylib.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

typedef void (*GetInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetFlagFunction)(dispatch_queue_t, void (^)(BOOL));
typedef void (*GetPIDFunction)(dispatch_queue_t, void (^)(int));
typedef Boolean (*SendCommandFunction)(int, NSDictionary *);
typedef void (*GetCommandsFunction)(dispatch_queue_t, void (^)(CFArrayRef));
typedef uint32_t (*CommandInfoCommandFunction)(CFTypeRef);
typedef Boolean (*CommandInfoEnabledFunction)(CFTypeRef);
typedef void (*SetElapsedTimeFunction)(double);

// The numbers of the commands the player offers that Island cares about.
enum { CommandNextTrack = 4, CommandPreviousTrack = 5, CommandSeek = 24 };

static void *MediaRemote(void) {
    static void *handle;
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    return handle;
}

static double Number(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : -1;
}

static NSString *Text(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

/// The commands the playing app has switched on, so the buttons only offer what the app can do (a single YouTube video,
/// for one, has no next or previous track).
static NSSet<NSNumber *> *EnabledCommands(void *library, dispatch_queue_t queue) {
    GetCommandsFunction getCommands = (GetCommandsFunction)dlsym(library, "MRMediaRemoteGetSupportedCommands");
    CommandInfoCommandFunction command = (CommandInfoCommandFunction)dlsym(library, "MRMediaRemoteCommandInfoGetCommand");
    CommandInfoEnabledFunction enabled = (CommandInfoEnabledFunction)dlsym(library, "MRMediaRemoteCommandInfoGetEnabled");
    if (!getCommands || !command || !enabled) return nil;   // unknown: the caller assumes everything works

    NSMutableSet<NSNumber *> *result = [NSMutableSet set];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    getCommands(queue, ^(CFArrayRef infos) {
        for (CFIndex index = 0; infos && index < CFArrayGetCount(infos); index++) {
            CFTypeRef info = CFArrayGetValueAtIndex(infos, index);
            if (enabled(info)) [result addObject:@(command(info))];
        }
        dispatch_semaphore_signal(done);
    });
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0) return nil;
    return result;
}

/// One reading of what is playing, as a JSON object. An empty object means nothing is playing.
static NSDictionary *Reading(void) {
    void *library = MediaRemote();
    GetInfoFunction getInfo = library ? (GetInfoFunction)dlsym(library, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    GetFlagFunction getPlaying = library ? (GetFlagFunction)dlsym(library, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    GetPIDFunction getPID = library ? (GetPIDFunction)dlsym(library, "MRMediaRemoteGetNowPlayingApplicationPID") : NULL;
    if (!getInfo) return @{ @"unsupported": @YES };

    __block NSDictionary *info = nil;
    __block BOOL playing = NO;
    __block int pid = 0;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    getInfo(queue, ^(NSDictionary *result) { info = result; dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    if (getPlaying) {
        getPlaying(queue, ^(BOOL result) { playing = result; dispatch_semaphore_signal(done); });
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }
    if (getPID) {
        getPID(queue, ^(int result) { pid = result; dispatch_semaphore_signal(done); });
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }

    NSString *title = Text(info, @"kMRMediaRemoteNowPlayingInfoTitle");
    if (!title.length) return @{};
    NSSet<NSNumber *> *commands = EnabledCommands(library, queue);

    NSMutableDictionary *reading = [NSMutableDictionary dictionary];
    reading[@"title"] = title;
    NSString *artist = Text(info, @"kMRMediaRemoteNowPlayingInfoArtist");
    if (artist.length) reading[@"artist"] = artist;
    NSString *album = Text(info, @"kMRMediaRemoteNowPlayingInfoAlbum");
    if (album.length) reading[@"album"] = album;
    double duration = Number(info, @"kMRMediaRemoteNowPlayingInfoDuration");
    if (duration > 0) reading[@"duration"] = @(duration);
    double elapsed = Number(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime");
    if (elapsed >= 0) reading[@"elapsed"] = @(elapsed);
    double rate = Number(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate");
    reading[@"rate"] = @(rate >= 0 ? rate : (playing ? 1 : 0));
    id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if ([timestamp isKindOfClass:[NSDate class]]) reading[@"timestamp"] = @([(NSDate *)timestamp timeIntervalSince1970]);
    reading[@"playing"] = @(playing);
    if (pid > 0) reading[@"pid"] = @(pid);
    if (commands) {
        reading[@"canNext"] = @([commands containsObject:@(CommandNextTrack)]);
        reading[@"canPrevious"] = @([commands containsObject:@(CommandPreviousTrack)]);
        reading[@"canSeek"] = @([commands containsObject:@(CommandSeek)]);
    }
    return reading;
}

void adapter_stream(void *interpreter, void *cv) {
    @autoreleasepool {
        // getppid() becomes 1 when Island is gone, so a crashed Island never leaves this running.
        while (getppid() != 1) {
            BOOL playing = NO;
            @autoreleasepool {
                NSDictionary *reading = Reading();
                playing = reading[@"title"] != nil;
                NSData *json = [NSJSONSerialization dataWithJSONObject:reading options:0 error:nil];
                if (json) {
                    fwrite(json.bytes, 1, json.length, stdout);
                    fputc('\n', stdout);
                    fflush(stdout);
                }
            }
            sleep(playing ? 1 : 3);
        }
    }
    exit(0);
}

void adapter_send(void *interpreter, void *cv) {
    @autoreleasepool {
        const char *text = getenv("ISLAND_MR_COMMAND");
        void *library = MediaRemote();
        SendCommandFunction send = library ? (SendCommandFunction)dlsym(library, "MRMediaRemoteSendCommand") : NULL;
        if (text && send) {
            send(atoi(text), nil);
            usleep(300 * 1000); // the command is asynchronous; let it leave before this process ends
        }
    }
}

void adapter_seek(void *interpreter, void *cv) {
    @autoreleasepool {
        const char *text = getenv("ISLAND_MR_SEEK");
        void *library = MediaRemote();
        SetElapsedTimeFunction seek = library ? (SetElapsedTimeFunction)dlsym(library, "MRMediaRemoteSetElapsedTime") : NULL;
        if (text && seek) {
            seek(atof(text));
            usleep(300 * 1000);
        }
    }
}
