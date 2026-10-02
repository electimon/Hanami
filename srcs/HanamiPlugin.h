#import <ObjFW/ObjFW.h>
#import "HanamiPluginResult.h"
#import "HanamiClasses.h"

// prototypes for plugins to include
Class HanamiPluginClass(void);

@protocol HanamiPlugin <OFObject>
@property (nonatomic, strong, readonly) OFString *name;
@property (nonatomic, strong, readonly) OFString *version;
@property (nonatomic, strong, readonly) OFString *author;
@optional
- (void)transformMap:(OFMutableDictionary *)varMap;
@optional
- (HanamiPluginResult *)handleRequest:(id<HanamiPluginRequestContextProtocol>)requestContext;
@end