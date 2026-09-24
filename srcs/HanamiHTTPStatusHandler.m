#import "HanamiHTTPStatusHandler.h"
#import "HanamiConfig.h"
#import "HanamiPrivateConfig.h"
#import "HanamiUtils.h"

@implementation HanamiHTTPStatusHandler

+ (OFString *)getStatusTemplate:(int)statusCode {
    return [HanamiUtils getTemplateAtIRI:[entriesPath IRIByAppendingPathComponent:[OFString stringWithFormat:@"%d.%@", statusCode, defaultFileExtension]] defaultValue:[HTMLStatus copy]];
}

+ (void)handleStatus:(int)statusCode response:(OFHTTPResponse *)response andVarMap:(OFMutableDictionary *)varMap {
    [varMap setValue:[OFString stringWithFormat:@"%d", statusCode] forKey:@"$status_code"];
    if ([varMap valueForKey:@"$int_error"])
        [varMap setValue:[varMap valueForKey:@"$int_error"] forKey:@"$error"];
    else
        [varMap setValue:OFHTTPStatusCodeString(statusCode) forKey:@"$error"];
    response.statusCode = statusCode;
	if ([[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"wrap_status_pages" defaultValue:@"1"] intValue])
		[HanamiUtils wrapResponse:response withBody:[HanamiUtils transformTemplate:[self getStatusTemplate:statusCode] varMap:varMap] andVarMap:varMap];
	else
    	[response writeString:[HanamiUtils transformTemplate:[self getStatusTemplate:statusCode] varMap:varMap]];
}
@end