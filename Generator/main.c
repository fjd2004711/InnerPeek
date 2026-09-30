// InnerPeek legacy Quick Look generator entry point.
//
// The modern App Extension path is never dispatched for ordinary folders on
// current macOS, so folder previews are served by this CFPlugIn generator.
// It is intentionally thin: all analysis and HTML rendering live in Swift
// (HTMLPreview.swift) behind `ip_render_preview`.
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Implemented in Swift via @_cdecl. Returns a +1 retained CFData or NULL.
extern void *ip_render_preview(const void *url);

typedef struct {
    void *conduitInterface;
    CFUUIDRef factoryID;
    UInt32 refCount;
} InnerPeekGeneratorPlugin;

static OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail,
                                        CFURLRef url, CFStringRef contentTypeUTI,
                                        CFDictionaryRef options, CGSize maxSize) {
    // Folder icons are drawn by Finder; decline so the system default is used.
    return kQLReturnNoError;
}

static void CancelThumbnailGeneration(void *thisInterface, QLThumbnailRequestRef thumbnail) {}

static OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview,
                                      CFURLRef url, CFStringRef contentTypeUTI,
                                      CFDictionaryRef options) {
    if (QLPreviewRequestIsCancelled(preview)) return noErr;
    CFDataRef html = (CFDataRef)ip_render_preview(url);
    if (!html) return noErr;
    if (QLPreviewRequestIsCancelled(preview)) { CFRelease(html); return noErr; }

    CFStringRef keys[] = {
        kQLPreviewPropertyTextEncodingNameKey,
        kQLPreviewPropertyMIMETypeKey,
        kQLPreviewPropertyWidthKey,
        kQLPreviewPropertyHeightKey,
    };
    int width = 760, height = 720;
    CFNumberRef w = CFNumberCreate(NULL, kCFNumberIntType, &width);
    CFNumberRef h = CFNumberCreate(NULL, kCFNumberIntType, &height);
    CFTypeRef values[] = { CFSTR("UTF-8"), CFSTR("text/html"), w, h };
    CFDictionaryRef props = CFDictionaryCreate(NULL, (const void **)keys, (const void **)values, 4,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
    QLPreviewRequestSetDataRepresentation(preview, html, kUTTypeHTML, props);
    CFRelease(props); CFRelease(w); CFRelease(h); CFRelease(html);
    return noErr;
}

static void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview) {}

static HRESULT PluginQueryInterface(void *thisInstance, REFIID iid, LPVOID *ppv);
static ULONG PluginAddRef(void *thisInstance);
static ULONG PluginRelease(void *thisInstance);

static QLGeneratorInterfaceStruct gInterface = {
    NULL,
    PluginQueryInterface,
    PluginAddRef,
    PluginRelease,
    GenerateThumbnailForURL,
    CancelThumbnailGeneration,
    GeneratePreviewForURL,
    CancelPreviewGeneration
};

static HRESULT PluginQueryInterface(void *thisInstance, REFIID iid, LPVOID *ppv) {
    CFUUIDRef interfaceID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, iid);
    if (CFEqual(interfaceID, kQLGeneratorCallbacksInterfaceID) ||
        CFEqual(interfaceID, IUnknownUUID)) {
        gInterface.AddRef(thisInstance);
        *ppv = thisInstance;
        CFRelease(interfaceID);
        return S_OK;
    }
    *ppv = NULL;
    CFRelease(interfaceID);
    return E_NOINTERFACE;
}

static ULONG PluginAddRef(void *thisInstance) {
    return ++((InnerPeekGeneratorPlugin *)thisInstance)->refCount;
}

static ULONG PluginRelease(void *thisInstance) {
    InnerPeekGeneratorPlugin *plugin = thisInstance;
    plugin->refCount--;
    if (plugin->refCount == 0) {
        CFUUIDRef factoryID = plugin->factoryID;
        if (factoryID) {
            CFPlugInRemoveInstanceForFactory(factoryID);
            CFRelease(factoryID);
        }
        free(plugin);
        return 0;
    }
    return plugin->refCount;
}

// Referenced by name from Info.plist (CFPlugInFactories).
void *InnerPeekGeneratorFactory(CFAllocatorRef allocator, CFUUIDRef typeID) {
    if (!CFEqual(typeID, kQLGeneratorTypeID)) return NULL;
    InnerPeekGeneratorPlugin *plugin = malloc(sizeof(InnerPeekGeneratorPlugin));
    plugin->conduitInterface = &gInterface;
    plugin->refCount = 1;
    plugin->factoryID = CFUUIDCreateFromString(
        kCFAllocatorDefault, CFSTR("7C1D3F52-6B0E-4D0A-9B8A-1F4E2A5C9D31"));
    CFPlugInAddInstanceForFactory(plugin->factoryID);
    return plugin;
}
