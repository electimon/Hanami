#import "../../srcs/HanamiPlugin.h"
#import "../../srcs/HanamiConfig.h"

@interface LastFMResponse : OFObject
@property (nonatomic, strong) OFString *title;
@property (nonatomic, strong) OFString *artist;
@property (nonatomic, strong) OFString *url;
@property (nonatomic, strong) OFDate *date;
@property (nonatomic, strong) OFString *imageUrl;
@property (nonatomic) BOOL nowPlaying;
@end

@implementation LastFMResponse
@end

@interface LastFMClient : OFObject <OFHTTPClientDelegate>
- (instancetype)initWithAPIKey:(OFString *)apikey andUsername:(OFString *)username;
- (OFString *)getLastPlayed;
- (OFString *)getNowPlaying;
- (LastFMResponse *)lastResponse;
@end

@interface LastFMPlugin : OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [LastFMPlugin class];
}

@implementation LastFMClient {
    OFTimer *timer;
    OFHTTPClient *client;
    OFHTTPRequest *request;
    LastFMResponse *lastResponse;
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
    self->lastResponse = [[LastFMResponse alloc] init];
    [self->timer fire];
    return self;
}

- (void)fillCache:(OFHTTPResponse *)resp {
    @synchronized (self) {
        @try {
            LastFMResponse *response = [[LastFMResponse alloc] init];
            OFXMLElement *elem = [OFXMLElement elementWithStream:resp];
            OFXMLElement *firstElem = [[[[elem elementsForName:@"recenttracks"] firstObject] elementsForName:@"track"] firstObject];
            OFXMLElement *lastElem = [[[[elem elementsForName:@"recenttracks"] firstObject] elementsForName:@"track"] lastObject];
            response.url = [[firstElem elementForName:@"url"] stringValue];
            response.title = [[firstElem elementForName:@"name"] stringValue];
            response.artist = [[firstElem elementForName:@"artist"] stringValue];
            if ([[firstElem elementForName:@"date"] attributeForName:@"uts"])
                response.date = [[OFDate alloc] initWithTimeIntervalSince1970:[[[[firstElem elementForName:@"date"] attributeForName:@"uts"] stringValue] longLongValue]];
            else
                response.nowPlaying = YES;
            OFArray *elems = [lastElem elementsForName:@"image"];
            if (elems != nil && elems.count > 0) {
                if (elems.count == 1)
                    response.imageUrl = [[elems firstObject] stringValue];
                else if (elems.count == 4)
                    response.imageUrl = [[elems objectAtIndex:2] stringValue];
                else
                    response.imageUrl = [[elems objectAtIndex:1] stringValue];
            } else {
                response.imageUrl = @"";
            }
            lastResponse = response;
        } @catch (OFException *ex) {
            OFLog(@"LastFMPlugin: Failed to get latest track info: %@, resp: %@", ex, resp);
        }
    }
}

- (OFString *)getLastPlayed {
    if (lastResponse.date != nil)
        return [OFString stringWithFormat:@"<a href=\"%@\">%@ by %@</a><br><small>Played on %@</small>", lastResponse.url, lastResponse.title, lastResponse.artist, [lastResponse.date dateStringWithFormat: @"%Y-%m-%d %H:%M:%S"]];
    return nil;
}

- (OFString *)getNowPlaying {
    return [OFString stringWithFormat:@"<a href=\"%@\">%@ by %@</a><br><small>Playing now as we speak!</small>", lastResponse.url, lastResponse.title, lastResponse.artist];
}

- (void)client:(nonnull OFHTTPClient *)remoteClient didPerformRequest:(nonnull OFHTTPRequest *)request response:(nullable OFHTTPResponse *)response exception:(nullable id)exception {
    if (exception != nil) {
        OFLog(@"LastFMPlugin: Got exception: %@", exception);
        [remoteClient close];
    } else
        [self fillCache:response];
}

- (LastFMResponse *)lastResponse {
    return lastResponse;
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
        [varMap setObject:client.lastResponse.title forKey:@"$lastfm::title"];
        [varMap setObject:client.lastResponse.artist forKey:@"$lastfm::artist"];
        [varMap setObject:client.lastResponse.url forKey:@"$lastfm::url"];
        [varMap setObject:client.lastResponse.imageUrl forKey:@"$lastfm::image_url"];
        [varMap setObject:[OFNumber numberWithBool:client.lastResponse.nowPlaying] forKey:@"$lastfm::now_playing"];
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