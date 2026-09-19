#import <ObjFW/ObjFW.h>

@interface HanamiFileManager : OFObject
+ (OFIRI *)IRIWithPath:(OFString *)path;
+ (BOOL)createDirectoryAndParents:(OFIRI *)dirPath;
@end