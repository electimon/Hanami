#import <ObjFW/ObjFW.h>

@interface HanamiConfig : OFObject
+ (instancetype)instanceFor:(OFString *)name;
+ (void)setConfigBasePath:(OFString *)basePath;
+ (OFIRI *)getConfigBasePath;
- (OFString *)valueForKey:(OFString *)key defaultValue:(OFString *)defaultValue;
- (void)setValue:(OFString *)value forKey:(nonnull OFString *)key;
@end