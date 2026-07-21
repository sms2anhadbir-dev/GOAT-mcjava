#import <stdint.h>
#import <device/device_types.h>
#import <CoreFoundation/CoreFoundation.h>
#import <mach/mach.h>

#define IO_OBJECT_NULL ((io_object_t)0)

typedef UInt32 IOOptionBits;

typedef mach_port_t io_object_t;
typedef io_object_t io_registry_entry_t;
// Not part of the public iOS SDK's headers (IOKit.framework's IOTypes.h is
// absent from the theos/sdks dump), so it's defined here to match Apple's
// real IOKit type - see the real IOTypes.h: typedef char io_string_t[512].
typedef char io_string_t[512];

extern mach_port_t kIOMainPortDefault;

extern kern_return_t IOObjectRelease(io_object_t object);

extern io_registry_entry_t IORegistryEntryFromPath(mach_port_t mainPort, io_string_t path);
extern CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);
