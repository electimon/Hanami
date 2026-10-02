#import "../../srcs/HanamiPlugin.h"

@interface DummyPlugin: OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [DummyPlugin class];
}

@implementation DummyPlugin
- (void)transformMap:(OFMutableDictionary *)varMap {
}

- (HanamiPluginResult *)handleRequest:(id<HanamiPluginRequestContextProtocol>)requestContext {
    return nil; // please return a valid object if you implement this
}

- (OFString *)name {
    return @"DummyPlugin";
}

- (OFString *)author {
    return @"Dummy";
}

- (OFString *)version {
    return @"1.0";
}

@end