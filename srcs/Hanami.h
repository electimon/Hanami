#import <ObjFW/ObjFW.h>

OF_ASSUME_NONNULL_BEGIN

// dlopen-based module loader with RTLD_GLOBAL, replaces OFModule for
// plugins that need to share ObjC runtime/ARC state with the host
@interface HanamiModule: OFObject
- (nullable instancetype)initWithPath: (OFString *)path;
- (nullable void *)addressForSymbol: (OFString *)symbol;
@end

@interface Hanami: OFObject <OFApplicationDelegate, OFHTTPServerDelegate> {
	OFHTTPServer *_server;
	OFMutableArray *_plugins;
	OFMutableArray *_pluginModules; // keeps HanamiModule (and thus dlopen handle) alive
	OFIRI *_entriesPath;
	OFIRI *_staticPath;
	OFIRI *_pluginsPath;
	OFArray *_excluded;
}
@property (nonatomic, strong) OFMutableArray *plugins;
@end

OF_ASSUME_NONNULL_END
