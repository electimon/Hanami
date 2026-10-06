#import <ObjFW/ObjFW.h>

static const OFString *HTMLHead = @"<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">\n"
"<html>\n"
"    <head>\n"
"        <meta http-equiv=\"content-type\" content=\"$content_type\" >\n"
"        <link rel=\"alternate\" type=\"application/rss+xml\" title=\"RSS\" href=\"$url/index.rss\" >\n"
"        <title>$blog_title $path_info_da $path_info_mo $path_info_yr</title>\n"
"    </head>\n"
"    <body>\n"
"        <div align=\"center\">\n"
"            <h1>$blog_title</h1>\n"
"            <p>$path_info_da $path_info_mo $path_info_yr</p>\n"
"        </div>\n";

static const OFString *HTMLStory = @"        <div>\n"
"            <h3><a name=\"$fn\">$title</a></h3>\n"
"            <div>$body</div>\n"
"            <p>posted at: $mo $da, $yr | path: <a href=\"$url$path\">$path</a> | <a href=\"$url$path/$fn.html\">permanent link to this entry</a></p>\n"
"        </div>\n";

static const OFString *HTMLFoot = @"        <div align=\"center\">\n"
"            <a href=\"http://blosxom.sourceforge.net/\"><img src=\"http://blosxom.sourceforge.net/images/pb_blosxom.gif\" alt=\"powered by blosxom\" border=\"0\" width=\"90\" height=\"33\" ></a>\n"
"        </div>\n"
"    </body>\n"
"</html>\n";

static const OFString *HTMLStatus = @"		<div>\n"
"            <h3>Hanami has encountered an error...</h3>\n"
"            <div>Status: $status_code, Error: $error</div>\n"
"        </div>\n";

static const OFString *HTMLContentType = @"text/html; charset=UTF-8";
