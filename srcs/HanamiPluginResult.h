#import <ObjFW/ObjFW.h>

@interface HanamiPluginResult : OFObject {
	int _statusCode;
	OFDictionary *_headers;
	OFString *_title;
	OFString *_body;
}
- (instancetype)initWithStatusCode:(int)statusCode title:(OFString *)title headers:(OFDictionary *)headers andBody:(OFString *)body;
- (instancetype)initWithStatusCode:(int)statusCode contentType:(OFString *)contentType title:(OFString *)title andBody:(OFString *)body;
- (instancetype)initWithStatusCode:(int)statusCode headers:(OFDictionary *)headers;
- (instancetype)initWithStatusCode:(int)statusCode contentType:(OFString *)contentType;
- (OFString *)render:(OFString *)template varMap:(OFDictionary *)varMap;
@property (nonatomic, readonly) int statusCode;
@property (nonatomic, readonly) OFDictionary *headers;
@property (nonatomic, readonly) OFString *title;
@property (nonatomic, readonly) OFString *body;
@end
