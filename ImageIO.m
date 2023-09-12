// Compile with clang -o tester tester.m -framework Foundation -fsanitize=address -framework CoreGraphics -framework AppKit
#include <Foundation/Foundation.h>
#include <Foundation/NSURL.h>
#include <dlfcn.h>
#include <stdint.h>
#include <sys/shm.h>
#include <dirent.h>

#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>

#define MAX_SAMPLE_SIZE 1000000
#define SHM_SIZE (4 + MAX_SAMPLE_SIZE)
unsigned char *shm_data;

bool use_shared_memory;
int fd;

int clear_shmem(const char *name) {
	munmap((void*)name, SHM_SIZE);
	//shm_unlink(name); //disabling this to avoid error
	close(fd);
	return 0;
}

int setup_shmem(const char *name)
{
	// get shared memory file descriptor (NOT a file)
	fd = shm_open(name, O_RDONLY, S_IRUSR | S_IWUSR);
	if (fd == -1)
	{
		printf("Error in shm_open\n");
		return 0;
	}

	// map shared memory to process address space
	shm_data = (unsigned char *)mmap(NULL, SHM_SIZE, PROT_READ, MAP_SHARED, fd, 0);
	if (shm_data == MAP_FAILED)
	{
		printf("Error in mmap\n");
		return 0;
	}

	return 1;
}

int FuzzMe(const char* filename){
	char *sample_bytes = NULL;
	uint32_t sample_size = 0;

	CGImageRef        myImage = NULL;
	CGImageRef        myThumbnailImage = NULL;

	CGImageSourceRef  myImageSource;

	CFDictionaryRef   myImageOptions = NULL;
	CFDictionaryRef   myThumbnailOptions = NULL;

	CFStringRef       myImageKeys[2];
	CFStringRef       myThumbnailKeys[3];

	CFTypeRef         myImageValues[2];
	CFTypeRef         myThumbnailValues[3];

	CFNumberRef       thumbnailSize = NULL;

	CFDataRef 				data = NULL;

	//NSImage* thumbnailImage;

	int imageSize = 100;

	// Set up options if you want them. The options here are for
	// caching the image in a decoded form and for using floating-point
	// values if the image format supports them.
	myImageKeys[0] = kCGImageSourceShouldCache;
	myImageValues[0] = (CFTypeRef)kCFBooleanTrue;
	myImageKeys[1] = kCGImageSourceShouldAllowFloat;
	myImageValues[1] = (CFTypeRef)kCFBooleanTrue;

	// Create the dictionary
	myImageOptions = CFDictionaryCreate(NULL, (const void **) myImageKeys,
			(const void **) myImageValues, 2,
			&kCFTypeDictionaryKeyCallBacks,
			& kCFTypeDictionaryValueCallBacks);

	if(use_shared_memory) {
		//shared memory code.
		sample_size = *(uint32_t *)(shm_data);
		if(sample_size > MAX_SAMPLE_SIZE) sample_size = MAX_SAMPLE_SIZE;
		sample_bytes = (char *)malloc(sample_size);
		memcpy(sample_bytes, shm_data + sizeof(uint32_t), sample_size);
		data = CFDataCreateWithBytesNoCopy(NULL, (const UInt8*)sample_bytes, sample_size, kCFAllocatorNull);

		// Create an image source from the image data.
		myImageSource = CGImageSourceCreateWithData(data, myImageOptions);
		
	}
	else{
		//normal file based operation
		// Get the URL for the pathname passed to the function.
		NSString *path = [NSString stringWithCString:filename encoding:NSASCIIStringEncoding];    
		NSURL *url = [NSURL fileURLWithPath:path];
		// Create an image source from the URL.
		myImageSource = CGImageSourceCreateWithURL((CFURLRef)url, myImageOptions);
		
	}

	// Make sure the image source exists before continuing
	if (myImageSource){
		// Create an image from the first item in the image source.
		myImage = CGImageSourceCreateImageAtIndex(myImageSource,
				0,
				NULL);
		// Make sure the image exists before continuing
		if (myImage){
			size_t width = CGImageGetWidth(myImage);
			size_t height = CGImageGetHeight(myImage);
			CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
			CGContextRef ctx = CGBitmapContextCreate(0, width, height, 8, 0, colorspace, 1);
			CGRect rect = CGRectMake(0, 0, width, height);
			CGContextDrawImage(ctx, rect, myImage);
			

			// Package the integer as a  CFNumber object. Using CFTypes allows you
			// to more easily create the options dictionary later.
			thumbnailSize = CFNumberCreate(NULL, kCFNumberIntType, &imageSize);

			// Set up the thumbnail options.
			myThumbnailKeys[0] = kCGImageSourceCreateThumbnailWithTransform;
			myThumbnailValues[0] = (CFTypeRef)kCFBooleanTrue;
			myThumbnailKeys[1] = kCGImageSourceCreateThumbnailFromImageIfAbsent;
			myThumbnailValues[1] = (CFTypeRef)kCFBooleanTrue;
			myThumbnailKeys[2] = kCGImageSourceThumbnailMaxPixelSize;
			myThumbnailValues[2] = (CFTypeRef)thumbnailSize;

			myThumbnailOptions = CFDictionaryCreate(NULL, (const void **) myThumbnailKeys,
					(const void **) myThumbnailValues, 2,
					&kCFTypeDictionaryKeyCallBacks,
					& kCFTypeDictionaryValueCallBacks);

			// Create the thumbnail image using the specified options.
			myThumbnailImage = CGImageSourceCreateThumbnailAtIndex(myImageSource,
					0,
					myThumbnailOptions);

 /*
			if (myThumbnailImage) {
				// Create an NSImage and set its properties to the thumbnail image
				// you just created.
				thumbnailImage = [[NSImage alloc] initWithCGImage:myThumbnailImage size:NSZeroSize];
				thumbnailImage.size = NSMakeSize(imageSize, imageSize);
				// Display the thumbnail image on the screen.
				[thumbnailImage drawAtPoint:NSMakePoint(0, 0) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
			}
             */
			CGColorSpaceRelease(colorspace);
			CGContextRelease(ctx);
		}
	}
	// Release the options dictionary and the image source
	// when you no longer need them.
   
    if(data){
        CFRelease(data);
    }
    if(myImageOptions){
        
        CFRelease(myImageOptions);
    }
    if(thumbnailSize){
        CFRelease(thumbnailSize);
    }
    if(myThumbnailOptions){
        CFRelease(myThumbnailOptions);
    }
    if(myImageSource){
        CFRelease(myImageSource);
    }
    if(myImage){
        CGImageRelease(myImage);
    }
    if(myThumbnailImage){
        CGImageRelease(myThumbnailImage);
    }
    
	if(sample_bytes) {
		free(sample_bytes);
	}
	return 0;
}

int main(int argc, const char * argv[]) {
	if(argc != 3) {
		printf("Usage: %s <-f|-m> <file or shared memory name>\n", argv[0]);
		return 0;
	}

	if(!strcmp(argv[1], "-m")) {
		use_shared_memory = true;
	} else if(!strcmp(argv[1], "-f")) {
		use_shared_memory = false;
	} else {
		printf("Usage: %s <-f|-m> <file or shared memory name>\n", argv[0]);
		return 0;
	}

	// map shared memory here as we don't want to do it
	// for every operation
	if(use_shared_memory) {
		if(!setup_shmem(argv[2])) {
			printf("Error mapping shared memory\n");
		}
	}
	FuzzMe(argv[2]);
/*
	if (use_shared_memory) {
		clear_shmem(argv[2]);
	}
*/
	return 0;
}

