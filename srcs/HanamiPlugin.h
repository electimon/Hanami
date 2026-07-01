#import <ObjFW/ObjFW.h>

// prototypes for plugins to include
Class HanamiPluginClass(void);

@protocol HanamiPlugin <OFObject>
@property (nonatomic, strong, readonly) OFString *name;
@property (nonatomic, strong, readonly) OFString *version;
@property (nonatomic, strong, readonly) OFString *author;
- (void)transformMap:(OFMutableDictionary *)varMap;
@end