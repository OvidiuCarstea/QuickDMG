#import "DMGHandler.h"
#include <sys/mount.h>

#define useLog 0

@implementation DMGHandler

- (void)dealloc
{
	[_statusMessage release];
	[_terminationMessage release];
	[_workingLocation release];
	[_devEntry release];
	[_mountPoint release];
	[_currentTask release];
	[super dealloc];
}

- (PipingTask *)hdiUtilTask
{
	PipingTask *task = [[PipingTask alloc] init];
	[task setLaunchPath:@"/usr/bin/hdiutil"];
	if (_workingLocation) [task setCurrentDirectoryPath:_workingLocation];
	return [task autorelease];
}

-(BOOL) checkPreviousTask:(NSNotification *)notification
{
#if useLog
	NSLog(@"start checkPreviousTask");
#endif
	PipingTask *dmg_task = [notification object];
	NSNotificationCenter *noticenter = [NSNotificationCenter defaultCenter];
	[noticenter removeObserver:self];
	
	if ([dmg_task terminationStatus] != 0) {
		self.terminationMessage = [dmg_task stderrString];
		if ([_terminationMessage hasSuffix:@".Trashes: Permission denied\n"]) {
#if useLog
			NSLog(@"success to delete .DS_Store");
#endif
			return YES;
		} else {
#if useLog
			NSLog(@"error occur");
#endif
			[self detachNow];
			self.terminationStatus = [dmg_task terminationStatus];
			[noticenter postNotificationName: @"DmgDidTerminationNotification" object:self];
			return NO;
		}
	} else {
		self.terminationMessage = nil;
	}
#if useLog	
	NSLog(@"termination status is 0");
	NSLog(@"end checkPreviousTask");
#endif
	return YES;
}

- (void) postStatusNotification: (NSString *) message
{
	self.statusMessage = message;
	NSDictionary* info = [NSDictionary dictionaryWithObject:message forKey:@"statusMessage"];
	[[NSNotificationCenter defaultCenter] postNotificationName: @"DmgProgressNotification"
														object:self userInfo:info];
}

-(void) launchAsCurrentTask:(PipingTask *)task
{
	self.currentTask = task;
	[task launch];
}

- (void)afterDetachDiskImage:(NSNotification *)notification
{
	[self checkPreviousTask:notification];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_delegate diskImageDetached:self];
}

- (PipingTask *)detachNow
{
	if (!_devEntry) {
		return nil;
	}	
	PipingTask *detach_task = [self hdiUtilTask];
	[detach_task setArguments:[NSArray arrayWithObjects:@"detach", _devEntry, nil]];
	[detach_task launch];
	self.devEntry = nil;
	self.mountPoint = nil;
	return detach_task;
}

- (void)abortTask
{
	self.statusMessage = NSLocalizedString(@"Canceling task.", @"");
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_currentTask terminate];
	[self detachNow];
}

- (void)detachDiskImage:(NSString *)dev
{
	if (!dev) {
		dev = self.devEntry;
		self.devEntry = nil;
		self.mountPoint = nil;
	}
	
	[self postStatusNotification:NSLocalizedString(@"Detaching a disk image.","")];
	PipingTask *dmg_task = [self hdiUtilTask];
	[dmg_task setArguments:[NSArray arrayWithObjects:@"detach", dev, nil]];
	[[NSNotificationCenter defaultCenter]
					addObserver:self selector:@selector(afterDetachDiskImage:) 
						name:NSTaskDidTerminateNotification object:dmg_task];
	[self launchAsCurrentTask:dmg_task];
}

- (void)attachDiskImage:(NSString *)path
{
#if useLog
	NSLog(@"start attachDiskImage");
#endif
	[self postStatusNotification: NSLocalizedString(@"Attaching a disk image.","")];
	PipingTask *dmg_task = [self hdiUtilTask];
	[dmg_task setArguments:[NSArray arrayWithObjects:@"attach",path,@"-noverify",
							@"-nobrowse",@"-plist",nil]];
	
	[[NSNotificationCenter defaultCenter]
		 addObserver:self selector:@selector(afterAttachDiskImage:) 
		 name:NSTaskDidTerminateNotification object:dmg_task];
	
	[self launchAsCurrentTask:dmg_task];
#if useLog
	NSLog(@"end attachDiskImage");
#endif
}

- (void)afterAttachDiskImage:(NSNotification *)notification
{
	[self checkPreviousTask:notification];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	if (_terminationStatus == 0 ) {
		PipingTask *previous_task = [notification object];
		NSDictionary *task_result = [[previous_task stdoutString] propertyList];
	#if useLog
		NSLog(@"%@", [task_result description]);
	#endif
		NSArray *entities = [task_result objectForKey:@"system-entities"];
		NSString *mount_point = nil;
		for (NSDictionary *dict in entities) {
			mount_point = [dict objectForKey:@"mount-point"];
			if (mount_point) {
				self.devEntry = [dict objectForKey:@"dev-entry"];
				self.mountPoint = mount_point;
				break;
			}
		}
	}
	[_delegate diskImageAttached:self];
}

- (void)afterDitto:(NSNotification *)notification
{
	[self checkPreviousTask:notification];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_delegate dittoFinished:self];
}

- (void)dittoPath:(NSString *)srcPath toPath:(NSString *)destPath
{
#if useLog
	NSLog(@"start dittoPath:");
#endif
	[self postStatusNotification: NSLocalizedString(@"Copying source files.","")];
	
	PipingTask * task = [[PipingTask new] autorelease];
	[task setLaunchPath:@"/usr/bin/ditto"];
	[task setArguments:[NSArray arrayWithObjects:@"--rsrc",srcPath,destPath,nil]];
	[[NSNotificationCenter defaultCenter] 
								addObserver:self selector:@selector(afterDitto:) 
									name:NSTaskDidTerminateNotification object:task];		
	
	[self launchAsCurrentTask:task];
#if useLog
	NSLog(@"end copySourceItems:");
#endif
}

+ (DMGHandler *)dmgHandlerWithDelegate:(id)object
{
	DMGHandler *h = [[self new] autorelease];
	h.delegate = object;
	return h;
}

@end
