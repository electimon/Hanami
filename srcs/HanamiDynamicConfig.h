#import "HanamiConfig.h"
#import "HanamiFileManager.h"

#define entriesPath [HanamiFileManager IRIWithPath:[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"entries_dir" defaultValue:@"entries"]]
#define excluded [[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"exclude" defaultValue:@""] componentsSeparatedByString:@" "]
#define pluginsPath [HanamiFileManager IRIWithPath:[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"plugin_dir" defaultValue:@"plugins"]]
#define staticPath [HanamiFileManager IRIWithPath:[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"static_dir" defaultValue:@"static"]]
#define statePath [HanamiFileManager IRIWithPath:[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"state_dir" defaultValue:@"state"]]
#define pluginsSupportPath [HanamiFileManager IRIWithPath:[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"plugin_support_dir" defaultValue:@"plugins-etc"]]
#define defaultFlavour [[HanamiConfig instanceFor:@"hanami"] valueForKey:@"default_flavour" defaultValue:@"html"]
#define defaultFileExtension [[HanamiConfig instanceFor:@"hanami"] valueForKey:@"file_extension" defaultValue:@"txt"]