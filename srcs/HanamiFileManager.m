#import "HanamiFileManager.h"
#import "HanamiConfig.h"

@implementation HanamiFileManager


+ (OFIRI *)IRIWithPath:(OFString *)path {
    return [[HanamiConfig getConfigBasePath] IRIByAppendingPathComponent:path];
}

+ (BOOL)createDirectoryAndParents:(OFIRI *)dirPath {
	@try {
		[[OFFileManager defaultManager] createDirectoryAtIRI:dirPath createParents:YES];
	} @catch (OFCreateDirectoryFailedException *ex) {
		if (ex.errNo == EEXIST)
			OFLog(@"Hanami: %@ already exists ^_^", dirPath);
		else
			@throw (ex); // rethrow just in case
	}
    return YES;
}

@end