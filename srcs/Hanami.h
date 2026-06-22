#import <ObjFW/ObjFW.h>

OF_ASSUME_NONNULL_BEGIN

@interface Hanami: OFObject <OFApplicationDelegate, OFHTTPServerDelegate> {
	OFHTTPServer *_server;
}

@end

OF_ASSUME_NONNULL_END
