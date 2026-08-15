#import "../../srcs/HanamiPlugin.h"
#import "../../srcs/HanamiConfig.h"

@interface LastFMClient : OFObject <OFHTTPClientDelegate>
- (instancetype)initWithAPIKey:(OFString *)apikey andUsername:(OFString *)username;
- (OFString *)getLastPlayed;
- (OFString *)getNowPlaying;
@end

@interface LastFMPlugin : OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [LastFMPlugin class];
}

@implementation LastFMClient {
    OFString *url;
    OFString *title;
    OFString *artist;
    OFDate *date;
    OFTimer *timer;
    OFHTTPClient *client;
    OFHTTPRequest *request;
}

- (instancetype)initWithAPIKey:(OFString *)apiKey andUsername:(OFString *)username {
    self = [super init];
    self->request = [[OFHTTPRequest alloc] initWithIRI:[OFIRI IRIWithString:[OFString stringWithFormat:@"https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user=%@&api_key=%@&limit=1", username, apiKey]]];
    self->client = [OFHTTPClient client];
    self->client.delegate = self;
    self->timer = [OFTimer scheduledTimerWithTimeInterval:180.0 repeats:YES block:^(OFTimer * _Nonnull timer){
        [self->client close];
        [self->client asyncPerformRequest:self->request];
    }];
    [self->timer fire];
    return self;
}

- (void)fillCache:(OFHTTPResponse *)resp {
    @synchronized (self) {
        @try {
            OFXMLElement *elem = [OFXMLElement elementWithStream:resp];
            elem = [[[[elem elementsForName:@"recenttracks"] firstObject] elementsForName:@"track"] firstObject];
            url = [[elem elementForName:@"url"] stringValue];
            title = [[elem elementForName:@"name"] stringValue];
            artist = [[elem elementForName:@"artist"] stringValue];
            if ([[elem elementForName:@"date"] attributeForName:@"uts"])
                date = [[OFDate alloc] initWithTimeIntervalSince1970:[[[[elem elementForName:@"date"] attributeForName:@"uts"] stringValue] longLongValue]];
            else
                date = nil;
        } @catch (OFException *ex) {
            OFLog(@"LastFMPlugin: Failed to get latest track info: %@, resp: %@", ex, resp);
        }
    }
}

- (OFString *)getLastPlayed {
    if (date)
        return [OFString stringWithFormat:@"<a href=\"%@\">%@ by %@</a><br><small>Played on %@</small>", url, title, artist, [date dateStringWithFormat: @"%Y-%m-%d %H:%M:%S"]];
    return nil;
}

- (OFString *)getNowPlaying { // this doesnt have the pattern above because worst case, like astronomical bit flip chance we still return something
    return [OFString stringWithFormat:@"<a href=\"%@\">%@ by %@</a><br><small>Playing now as we speak!</small>", url, title, artist];
}

- (void)client:(nonnull OFHTTPClient *)client didPerformRequest:(nonnull OFHTTPRequest *)request response:(nullable OFHTTPResponse *)response exception:(nullable id)exception {
    if (exception != nil) {
        OFLog(@"LastFMPlugin: Got exception: %@", exception);
        [client close];
    } else
        [self fillCache:response];
}

@end

@implementation LastFMPlugin {
    LastFMClient *client;
}

- (instancetype)init {
    self = [super init];
    HanamiConfig *config = [HanamiConfig instanceFor:@"lastfm"];
    OFString *apiKey = [config valueForKey:@"api_key" defaultValue:@""];
    OFString *username = [config valueForKey:@"username" defaultValue:@""];
    if (apiKey.length < 1 || username.length < 1) {
        OFLog(@"LastFMPlugin: Wrong or no | API Key or Username | set!");
        return nil;
    }
    self->client = [[LastFMClient alloc] initWithAPIKey:apiKey andUsername:[config valueForKey:@"username" defaultValue:@""]];
    return self;
}

- (void)transformMap:(OFMutableDictionary *)varMap {
    OFString *nowPlaying;
    OFString *lastPlayed;
    @synchronized (client) {
        nowPlaying = [client getNowPlaying];
        lastPlayed = [client getLastPlayed];
    }
    if (lastPlayed != nil)
        [varMap setObject:lastPlayed forKey:@"$lastfm::status"];
    else
        [varMap setObject:nowPlaying forKey:@"$lastfm::status"];
}

- (OFString *)name {
    return @"LastFMPlugin";
}

- (OFString *)author {
    return @"Renn";
}

- (OFString *)version {
    return @"1.0";
}

@end