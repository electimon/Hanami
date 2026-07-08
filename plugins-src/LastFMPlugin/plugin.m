#import "../../srcs/HanamiPlugin.h"

@interface LastFMClient : OFObject <OFHTTPClientDelegate>
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
    OFString *date;
    OFTimer *timer;
    OFHTTPClient *client;
    OFHTTPRequest *request;
}

- (instancetype)init {
    self = [super init];
    self->request = [[OFHTTPRequest alloc] initWithIRI:[OFIRI IRIWithString:@"https://google.com"]];
    self->client = [OFHTTPClient client];
    self->client.delegate = self;
    self->timer = [[OFTimer alloc] initWithFireDate:[OFDate dateWithTimeIntervalSinceNow:5.0] interval:120.0 target:self selector:@selector(fillCache) object:nil repeats:YES];
    OFLog(@"Client made");
    [self->timer fire];
    return self;
}

- (void)fillCache {
    OFLog(@"YOU TOO");
    OFLog(@"test: %@", [client performRequest:request]);
}

- (OFString *)getLastPlayed {
    return @"";
}

- (void)client:(nonnull OFHTTPClient *)client didPerformRequest:(nonnull OFHTTPRequest *)request response:(nullable OFHTTPResponse *)response exception:(nullable id)exception {
    OFLog(@"its here");
    OFLog(@"HELLO %d", response.statusCode);
}

- (void) client: 		(OFHTTPClient *) 	client
didReceiveHeaders: 		(OFDictionary *) 	headers
statusCode: 		(short) 	statusCode
request: 		(OFHTTPRequest *) 	request {
    OFLog(@"%@ %d", headers, statusCode);
}

@end

@implementation LastFMPlugin {
    LastFMClient *client;
}

- (instancetype)init {
    self = [super init];
    self->client = [[LastFMClient alloc] init];
    OFLog(@"Made !");
    return self;
}

- (void)transformMap:(OFMutableDictionary *)varMap {

}

- (HanamiPluginResult *)handleRequest:(OFHTTPRequest *)request response:(OFHTTPResponse *)response andVarMap:(OFMutableDictionary *)varMap {
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