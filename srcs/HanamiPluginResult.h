#import <ObjFW/ObjFW.h>

@interface HanamiPluginResult : OFObject
- (instancetype)initWithStatusCode:(int)statusCode contentType:(OFString *)contentType \
    title:(OFString *)title andBody:(OFString *)body;
- (OFString *)render:(OFString *)template varMap:(OFDictionary *)varMap;
@property (nonatomic, readonly) int statusCode;
@property (nonatomic, readonly) OFString *contentType;
@property (nonatomic, readonly) OFString *title;
@property (nonatomic, readonly) OFString *body;
@end