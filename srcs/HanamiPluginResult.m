#import "HanamiPluginResult.h"
#import "HanamiUtils.h"

@implementation HanamiPluginResult
- (instancetype)initWithStatusCode:(int)statusCode contentType:(OFString *)contentType \
    title:(OFString *)title andBody:(OFString *)body {
    self = [super init];
    self->_statusCode = statusCode;
    self->_contentType = contentType;
    self->_title = title;
    self->_body = body;
    return self;
}

- (OFString *)render:(OFString *)template varMap:(OFDictionary *)varMap {
    OFMutableDictionary *localVarMap = [varMap mutableCopy];

    // ideally eventually thisll be configurable, but for dynamic plugin stuff
    // we set the date to just the current date provided by the date plugin
    [localVarMap setValue:[[localVarMap valueForKey:@"$date::month"] substringToIndex:3] forKey:@"$mo"];
    [localVarMap setValue:[localVarMap valueForKey:@"$date::day"] forKey:@"$da"];
    [localVarMap setValue:[localVarMap valueForKey:@"$date::year"] forKey:@"$yr"];
	[localVarMap setValue:self.title forKey:@"$title"];
	[localVarMap setValue:self.body forKey:@"$body"];
	// [localVarMap setValue:[self.path.lastPathComponent stringByDeletingPathExtension] forKey:@"$fn"];
	// the reason we do the \\ to / is because on windows stringByDeletingLastPathComponent returns the appropriate path component divider for the runtime os
	// [localVarMap setValue:[[self.relPath stringByDeletingLastPathComponent] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] forKey:@"$path"];
    return [HanamiUtils transformTemplate:template varMap:localVarMap];
}
@end