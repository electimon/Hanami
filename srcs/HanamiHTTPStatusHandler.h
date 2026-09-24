#import <ObjFW/ObjFW.h>

typedef enum {
	HTTP_STATUS_400 = 400,	// RFC9110, Bad Request
	HTTP_STATUS_401,		// RFC9110, Unauthorized
	HTTP_STATUS_403 = 403,	// RFC9110, Forbidden
	HTTP_STATUS_404,		// RFC9110, Not Found
	HTTP_STATUS_405,    	// RFC9110, Method not Allowed
	HTTP_STATUS_410 = 410,	// RFC9110, Gone
} html_client_error_t;

typedef enum {
	HTTP_STATUS_500 = 500,	// RFC9110, Internal Server Error
} html_server_error_t;

@interface HanamiHTTPStatusHandler : OFObject
+ (void)handleStatus:(int)statusCode response:(OFHTTPResponse *)response andVarMap:(OFMutableDictionary *)varMap;
@end