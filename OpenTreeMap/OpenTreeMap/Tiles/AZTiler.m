//
//  AZTiler.m
//  OpenTreeMap
//
//  Created by Adam Hinz on 8/7/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "AZTileRenderer2.h"
#import "AZTiler.h"

////////////////////////////////////////////////////////////////////////////////
/*************               Helper classes                        ************/
////////////////////////////////////////////////////////////////////////////////

@implementation AZRenderedTile

@synthesize image, pendingEdges;

-(id)init {
    self = [super init];
    if (self) {
        self.image = nil;
        self.pendingEdges = [NSMutableSet setWithObjects:
                                              kAZNorth,kAZNorthEast,kAZEast,kAZSouthEast,
                                          kAZSouth,kAZSouthWest,kAZWest,kAZNorthWest,nil];
    }
    return self;
}

@end

@interface AZTileDownloadRequest : NSObject

@property (nonatomic,assign) MKCoordinateRegion region;
@property (nonatomic,assign) MKMapRect mapRect;
@property (nonatomic,assign) MKZoomScale zoomScale;

-(id)initWithRegion:(MKCoordinateRegion)r mapRect:(MKMapRect)mr zoomScale:(MKZoomScale)zs;

-(NSString *)stringFromCoordinateRegion;

@end

@implementation AZTileDownloadRequest

@synthesize region, mapRect, zoomScale;

-(id)initWithRegion:(MKCoordinateRegion)r mapRect:(MKMapRect)mr zoomScale:(MKZoomScale)zs {
    self = [super init];
    if (self) {
        self.region = r;
        self.mapRect = mr;
        self.zoomScale = zs;
    }
    return self;
}

-(NSString *)stringFromCoordinateRegion {
    return [NSString stringWithFormat:@"%f,%f,%f,%f",
                     region.center.latitude,
                     region.center.longitude,
                     region.span.latitudeDelta,
                     region.span.longitudeDelta];
}

-(NSUInteger)hash {
    return [[NSString stringWithFormat:@"%@:%@:%f",
                      [self stringFromCoordinateRegion],
                      MKStringFromMapRect(mapRect),
                      zoomScale] hash];
}

-(BOOL)isEqual:(id)other {
    return [other hash] == [self hash];
}

@end

////////////////////////////////////////////////////////////////////////////////
/*************               Main Event                            ************/
////////////////////////////////////////////////////////////////////////////////


@interface AZTiler ()

/**
 * Determine the direction of the 'to' tile relative to the 'from' tile.
 * For example:
 * If the 'from' tile is in the center of the screen and the 'to' tile
 * is directly above it this method returns kAZNorth
 *
 * @param from 'Center of the world'
 * @param to the other tile to calculate, relative to 'from'
 */
-(AZDirection)directionFrom:(AZTile *)from to:(AZTile *)to;

-(MKMapRect)translateMapRect:(MKMapRect)m x:(double)x y:(double)y;

@end

@implementation AZTiler

@synthesize renderCallback, filters;

-(id)init {
    self = [super init];
    if (self) {
        tiles = [NSMutableDictionary dictionary];
        renderedTiles = [NSMutableDictionary dictionary];
        waitingForRenderOpQueue = [[NSOperationQueue alloc] init];
        waitingForRenderQueue = [NSMutableOrderedSet orderedSet];
        waitingForDownloadOpQueue = [[NSOperationQueue alloc] init];
        waitingForDownloadQueue = [NSMutableOrderedSet orderedSet];

        waitingForRenderOpQueue.maxConcurrentOperationCount = 1;
    }
    return self;
}

-(void)sendTileRequestWithMapRect:(MKMapRect)mapRect
                        zoomScale:(MKZoomScale)zs
                           region:(MKCoordinateRegion)region {

    AZTile *tile = [tiles objectForKey:[AZTile tileKeyWithMapRect:mapRect zoomScale:zs]];
    if (tile == nil) {
        AZTileDownloadRequest *dlreq = [[AZTileDownloadRequest alloc] 
                                               initWithRegion:region
                                                      mapRect:mapRect
                                                    zoomScale:zs];
        [self enqueueObject:dlreq
                    onQueue:waitingForDownloadQueue
                     withOp:waitingForDownloadOpQueue
                 onComplete:@selector(doAsyncTileDownload:)];
    } else {
        [self enqueueObject:tile
                    onQueue:waitingForRenderQueue
                     withOp:waitingForRenderOpQueue
                 onComplete:@selector(renderTile:)];
    }   
}

-(UIImage *)getImageForMapRect:(MKMapRect)mapRect zoomScale:(MKZoomScale)zoomScale {
    return [[renderedTiles objectForKey:[AZTile tileKeyWithMapRect:mapRect
                                                       zoomScale:zoomScale]] image];
}

-(void)setFilters:(OTMFilters *)f {
    filters = f;

    // Clear all tiles
    @synchronized (tiles) {
        [tiles removeAllObjects];
        [renderedTiles removeAllObjects];
    }
}

-(void)clearTilesWithZoomScale:(MKZoomScale)zoomScale andPoints:(BOOL)points {
    NSUInteger count = 0;
    @synchronized (tiles) {
        for(NSString *key in [tiles allKeys]) {
            if ([key hasSuffix:[NSString stringWithFormat:@"%f", zoomScale]]) {
                count++;
                if (points) { [tiles removeObjectForKey:key]; }
                [renderedTiles removeObjectForKey:key];
            }
        }
    }
    NSLog(@"[AZTiler] Purged %d tiles",count);
}

-(void)clearTilesNotAtZoomScale:(MKZoomScale)zoomScale andPoints:(BOOL)points {
    NSUInteger count = 0;
    @synchronized (tiles) {
        for(NSString *key in [tiles allKeys]) {
            if (![key hasSuffix:[NSString stringWithFormat:@"%f", zoomScale]]) {
                count++;
                if (points) { [tiles removeObjectForKey:key]; }
                [renderedTiles removeObjectForKey:key];
            }
        }
    }
    NSLog(@"[AZTiler] Purged %d tiles",count);
}

-(void)clearTilesContainingPoint:(MKMapPoint)mapPoint andPoints:(BOOL)points {
    @synchronized (tiles) {
        for(AZTile *tile in [tiles allValues]) {            
            if (MKMapRectContainsPoint(tile.mapRect, mapPoint)) {
                NSArray *matchingTiles = [[self tilesSurroundingMapRect:tile.mapRect
                                                              zoomScale:tile.zoomScale] allValues];

                [renderedTiles removeObjectForKey:[AZTile tileKey:tile]];
                if (points) { [tiles removeObjectForKey:[AZTile tileKey:tile]]; }

                for(AZTile *atile in matchingTiles) {
                    [renderedTiles removeObjectForKey:[AZTile tileKey:atile]];
                    if (points) { [tiles removeObjectForKey:[AZTile tileKey:atile]]; }
                }
            }
        }
    }
}

////////////////////////////////////////////////////////////////////////////////

/**
 * Send a request to the server to download tiles
 * for a given tile request. Once the tiles have finished downloaded
 * they are automatically put into the render queue
 */
-(void)doAsyncTileDownload:(AZTileDownloadRequest *)dlreq {
    if ([NSThread isMainThread]) {
        [NSException raise:@"main thread exception" format:@""];
    }

    MKCoordinateRegion region = dlreq.region;

    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                                         [NSString stringWithFormat:@"%f,%f,%f,%f", 
                                                                   region.center.longitude - region.span.longitudeDelta / 2.0,
                                                                   region.center.latitude - region.span.latitudeDelta / 2.0,
                                                                   region.center.longitude + region.span.longitudeDelta / 2.0,
                                                                   region.center.latitude + region.span.latitudeDelta / 2.0, 
                                                                   nil], @"bbox", nil];
    if (filters) {
        [params addEntriesFromDictionary:[filters filtersDict]];
    }

    [[[OTMEnvironment sharedEnvironment] tileRequest] getRaw:@"tiles"
                                                      params:params
                                                        mime:@"otm/trees"
                                                    callback:[OTMAPI liftResponse:^(id data, NSError* error)
       {
           // Since this is an AZHttpRequest callback we are on the main thread.
           // To avoid blocking, we do everything on a background thread
           dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                   if ([NSThread isMainThread]) {
                       [NSException raise:@"main thread exception" format:@""];
                   }

                   AZPointParserError parseError = 0;
                   NSUInteger nPoints;
                   AZPoint **pointsRaw = parseData([data bytes], [data length], &nPoints, &parseError);

                   if (parseError != 0) {
                       NSLog(@"errororororor");
                   } else {
                       // Wrap the points in an NSValue
                       AZPointerArrayWrapper *points = [AZPointerArrayWrapper wrapperWithPointer:pointsRaw 
                                                                                          length:nPoints
                                                                                 deallocCallback:parserFreePoints()];

                       // Get all surrounding tiles               
                       //TODO: Not sure we need this @sync block here
                       // but it seems like it would be bad if we grabbed tiles from
                       // the dictionary, modify them, and put them back. Other threads
                       // could swoop in at that time and it would be bad news bears
                       @synchronized(tiles) {
                           NSDictionary *surroundingTiles = [self tilesSurroundingMapRect:dlreq.mapRect
                                                                                zoomScale:dlreq.zoomScale];
                   
                           NSMutableDictionary *surroundingPoints = [NSMutableDictionary dictionary];

                           for(id key in surroundingTiles) {
                               [surroundingPoints setObject:(id)[[surroundingTiles objectForKey:key] points] forKey:key];
                           }

                           // Create the new tile
                           AZTile *tile = [[AZTile alloc] initWithPoints:points
                                                             borderTiles:surroundingPoints
                                                                 mapRect:dlreq.mapRect
                                                               zoomScale:dlreq.zoomScale];

                           // Insert tile into cache
                           [tiles setObject:tile forKey:[AZTile tileKey:tile]];

                           // Update the surrounding tiles
                           NSMutableArray *newTiles = [NSMutableArray array];
                           for(AZTile *atile in [surroundingTiles allValues]) {
                               AZTile *newTile = [atile createTileWithNeighborTile:tile
                                                                       atDirection:[self directionFrom:atile to:tile]];
                       
                               [tiles setObject:newTile forKey:[AZTile tileKey:newTile]];
                               [newTiles addObject:newTile];
                           }

                           NSLog(@"Tile load turned into %d renders", [newTiles count]);
                           [newTiles addObject:tile];
                   
                           for(AZTile *atile in newTiles) {
                               [self enqueueObject:atile
                                           onQueue:waitingForRenderQueue
                                            withOp:waitingForRenderOpQueue
                                        onComplete:@selector(renderTile:)];
                           }
                       }
                   }
               });
       }]];
}

-(AZDirection)inverse:(AZDirection)d {
    if ([d isEqualToString:kAZNorth]) return kAZSouth;
    if ([d isEqualToString:kAZNorthEast]) return kAZSouthWest;
    if ([d isEqualToString:kAZEast]) return kAZWest;
    if ([d isEqualToString:kAZSouthEast]) return kAZNorthWest;
    if ([d isEqualToString:kAZSouth]) return kAZNorth;
    if ([d isEqualToString:kAZSouthWest]) return kAZNorthEast;
    if ([d isEqualToString:kAZWest]) return kAZEast;
    if ([d isEqualToString:kAZNorthWest]) return kAZSouthEast;
    return nil;
}

-(void)renderTile:(AZTile *)tile {
    if ([NSThread isMainThread]) {
        [NSException raise:@"main thread exception" format:@""];
    }

    // It's possible a fresher version of the tile exists...
    AZTile *fresh = [tiles objectForKey:[AZTile tileKey:tile]];
    
    if (fresh) {
        tile = fresh;
    }
    
    AZRenderedTile *rtile = [renderedTiles objectForKey:[AZTile tileKey:tile]];
    rtile = [AZTileRenderer2 drawTile:tile renderedTile:rtile filters:filters];

    [renderedTiles setObject:rtile forKey:[AZTile tileKey:tile]];
    
    if (renderCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
                renderCallback(rtile.image, tile.fullyLoaded, tile.mapRect, tile.zoomScale);
            });
    }
}

-(void)sortWithMapRect:(MKMapRect)mapRect zoomScale:(MKZoomScale)zoomScale {
    NSComparator cmp = ^(AZTile *a, AZTile *b) {
            // Use zoom level first
            if (a.zoomScale != b.zoomScale) {
                // Pick the zoom level closest to our current one
                int zoomDiffA = ABS(a.zoomScale - zoomScale);
                int zoomDiffB = ABS(b.zoomScale - zoomScale);
                if (zoomDiffA < zoomDiffB) { // A is closer
                    return (NSComparisonResult)NSOrderedDescending; // B is before A
                } else if (zoomDiffA > zoomDiffB) { // B is closer
                    return (NSComparisonResult)NSOrderedAscending; // A is before B in the array
                } else { // Equal zoom values, queue in order of distance
                    return (NSComparisonResult)[self distanceOrdering:a to:b visibleMapRect:mapRect];
                }
            } else { // zoom scale is the same
                return (NSComparisonResult)[self distanceOrdering:a to:b visibleMapRect:mapRect];
            }
    };

    @synchronized(waitingForRenderQueue) {
        [waitingForRenderQueue sortUsingComparator:cmp];
    }

    @synchronized(waitingForDownloadQueue) {
        [waitingForDownloadQueue sortUsingComparator:cmp];
    }

    NSLog(@"Sorted tile request queues");
}


//////////////////////////////////////////////////////////////////////////

-(MKMapRect)translateMapRect:(MKMapRect)m x:(double)x y:(double)y {
    return MKMapRectMake(m.origin.x+x,m.origin.y+y,m.size.width,m.size.height);
}

-(NSDictionary *)tilesSurroundingMapRect:(MKMapRect)mapRect zoomScale:(MKZoomScale)zoomScale {
    double width = mapRect.size.width;
    double height = mapRect.size.width;

    MKMapRect northRect     = [self translateMapRect:mapRect x:0      y:height];
    MKMapRect northEastRect = [self translateMapRect:mapRect x:width  y:height];
    MKMapRect eastRect      = [self translateMapRect:mapRect x:width  y:0];
    MKMapRect southEastRect = [self translateMapRect:mapRect x:width  y:-height];
    MKMapRect southRect     = [self translateMapRect:mapRect x:0      y:-height];
    MKMapRect southWestRect = [self translateMapRect:mapRect x:-width y:-height];
    MKMapRect westRect      = [self translateMapRect:mapRect x:-width y:0];
    MKMapRect northWestRect = [self translateMapRect:mapRect x:-width y:height];

    AZTile *north     = [tiles objectForKey:[AZTile tileKeyWithMapRect:northRect     zoomScale:zoomScale]];
    AZTile *northEast = [tiles objectForKey:[AZTile tileKeyWithMapRect:northEastRect zoomScale:zoomScale]];
    AZTile *east      = [tiles objectForKey:[AZTile tileKeyWithMapRect:eastRect      zoomScale:zoomScale]];
    AZTile *southEast = [tiles objectForKey:[AZTile tileKeyWithMapRect:southEastRect zoomScale:zoomScale]];
    AZTile *south     = [tiles objectForKey:[AZTile tileKeyWithMapRect:southRect     zoomScale:zoomScale]];
    AZTile *southWest = [tiles objectForKey:[AZTile tileKeyWithMapRect:southWestRect zoomScale:zoomScale]];
    AZTile *west      = [tiles objectForKey:[AZTile tileKeyWithMapRect:westRect      zoomScale:zoomScale]];
    AZTile *northWest = [tiles objectForKey:[AZTile tileKeyWithMapRect:northWestRect zoomScale:zoomScale]];

    NSMutableDictionary *neighbors = [NSMutableDictionary dictionary];

    if (north) {
        [neighbors setObject:north forKey:kAZNorth];
    }

    if (northEast) {
        [neighbors setObject:northEast forKey:kAZNorthEast];
    }

    if (east) {
        [neighbors setObject:east forKey:kAZEast];
    }

    if (southEast) {
        [neighbors setObject:southEast forKey:kAZSouthEast];
    }

    if (south) {
        [neighbors setObject:south forKey:kAZSouth];
    }

    if (southWest) {
        [neighbors setObject:southWest forKey:kAZSouthWest];
    }

    if (west) {
        [neighbors setObject:west forKey:kAZWest];
    }

    if (northWest) {
        [neighbors setObject:northWest forKey:kAZNorthWest];
    }
    
    return neighbors;
}

-(AZDirection)directionFrom:(AZTile *)from to:(AZTile *)to {
    double fromX = from.mapRect.origin.x;
    double fromY = from.mapRect.origin.y;

    double toX = to.mapRect.origin.x;
    double toY = to.mapRect.origin.y;

    double wiggle = 1; // 1 meter

    BOOL east = toX > fromX + wiggle;
    BOOL west = toX < fromX - wiggle;
    BOOL south = toY < fromY - wiggle;
    BOOL north = toY > fromY + wiggle;

    if (north && west) { return kAZNorthWest; }
    if (north && east) { return kAZNorthEast; }
    if (south && west) { return kAZSouthWest; }
    if (south && east) { return kAZSouthEast; }
    if (north) { return kAZNorth; }
    if (south) { return kAZSouth; }
    if (east) { return kAZEast; }
    if (west) { return kAZWest; }

    return nil;
}

-(void)enqueueObject:(id)obj 
             onQueue:(NSMutableOrderedSet *)queue 
              withOp:(NSOperationQueue *)opQueue
          onComplete:(SEL)selector {

    @synchronized(queue) {
        [queue addObject:obj];
        [opQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
                    if ([NSThread isMainThread]) {
                        [NSException raise:@"main thread exception" format:@""];
                    }

                    @synchronized (queue) {
                        id ar = nil;
                        if ([queue count] > 0) {
                            ar = [queue lastObject];
                            [queue removeObjectAtIndex:[queue count] - 1];
                        }
                        if (ar) {
                            [self performSelector:selector withObject:ar];
                        }
                    }
                }]];
    }
}

-(NSComparisonResult)distanceOrdering:(AZTile *)a to:(AZTile *)b visibleMapRect:(MKMapRect)visibleMapRect {
    double dist2a = [self distanceTo:a.mapRect visibleMapRect:visibleMapRect];
    double dist2b = [self distanceTo:b.mapRect visibleMapRect:visibleMapRect];
    if (dist2a < dist2b) { // A is closer
        return NSOrderedDescending; // B is before A
    } else if (dist2a > dist2b) {
        return NSOrderedAscending; // A is before B
    } else { // equal
        return NSOrderedSame;
    }
}

// returns distance^2 from the center of the visible rect to the center of
// r
-(double)distanceTo:(MKMapRect)r visibleMapRect:(MKMapRect)visibleMapRect {
    double cx = r.origin.x + r.size.width/2.0;
    double cy = r.origin.y + r.size.height/2.0;

    double vx = visibleMapRect.origin.x + visibleMapRect.size.width/2.0;
    double vy = visibleMapRect.origin.y + visibleMapRect.size.height/2.0;

    return (cx - vx)*(cx - vx) + (cy-vy)*(cy-vy);
}


@end