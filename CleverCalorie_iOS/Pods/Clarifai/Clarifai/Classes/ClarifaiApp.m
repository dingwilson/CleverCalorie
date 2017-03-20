//
//  ClarifaiApp.m
//  ClarifaiApiDemo
//
//  Created by John Sloan on 9/1/16.
//  Copyright © 2016 Clarifai, Inc. All rights reserved.
//

#import "ClarifaiApp.h"
#import "NSArray+Clarifai.h"
#import "ClarifaiSearchResult.h"
#import "ClarifaiSearchTerm.h"

/** OAuth access token response. */
@interface ClarifaiAccessTokenResponse : NSObject
@property (strong, nonatomic) NSString *accessToken;
@property (assign, nonatomic) NSTimeInterval expiresIn;
@end

@implementation ClarifaiAccessTokenResponse

- (instancetype)initWithDictionary:(NSDictionary *)dict {
  self = [super init];
  if (self) {
    _accessToken = dict[@"access_token"];
    _expiresIn = MAX([dict[@"expires_in"] doubleValue], kMinTokenLifetime);
  }
  return self;
}

@end


@interface ClarifaiApp ()

@property (assign, nonatomic) BOOL authenticating;
@property (strong, nonatomic) NSString *appID;
@property (strong, nonatomic) NSString *appSecret;
@property (strong, nonatomic) NSDate *accessTokenExpiration;
@property (strong, nonatomic) NSDictionary *predictionTypes;
@property (strong, nonatomic) NSDictionary *modelTypes;

@end


@implementation ClarifaiApp

- (instancetype)initWithAppID:(NSString *)appID appSecret:(NSString *)appSecret {
  self = [super init];
  if (self) {
    _appID = appID;
    _appSecret = appSecret;
    
    // Configure AFNetworking:
    _manager = [AFHTTPRequestOperationManager manager];
    _manager.operationQueue.maxConcurrentOperationCount = 4;
    _manager.requestSerializer = [AFJSONRequestSerializer serializer];
    _manager.responseSerializer = [AFJSONResponseSerializer serializer];
    _manager.responseSerializer.acceptableContentTypes = [[NSSet alloc] initWithArray:@[@"application/json"]];
    _manager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    _predictionTypes =
    @{
      @(ClarifaiPredictionTypeAny): @"or_terms",
      @(ClarifaiPredictionTypeAll): @"and_terms",
      @(ClarifaiPredictionTypeNot): @"not_terms"
      };
    
    _modelTypes = @{
                    @(ClarifaiModelTypeEmbed): @"embed",
                    @(ClarifaiModelTypeConcept): @"concept",
                    @(ClarifaiModelTypeDetection): @"detection",
                    @(ClarifaiModelTypeCluster): @"cluster",
                    @(ClarifaiModelTypeColor): @"color"
                    };
    
    [self loadAccessToken];
  }
  return self;
}

#pragma mark - inputs

- (void)addInputs:(NSArray <ClarifaiInput *> *)inputs completion:(ClarifaiInputsCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/inputs"];
    NSMutableArray *inputsArray = [NSMutableArray array];
    for (int i = 0; i < inputs.count; i++) {
      ClarifaiInput *input = inputs[i];
      
      NSMutableDictionary *inputEntry = [NSMutableDictionary dictionary];
      
      // set inputID if one was provided
      if (![input.inputID isEqual: @""] && input.inputID != nil) {
        inputEntry[@"id"] = input.inputID;
      }
      
      if ([input isKindOfClass:[ClarifaiImage class]]) {
        // set data dict (contains image and tags).
        NSMutableDictionary *data = [NSMutableDictionary dictionary];
        // add url or imageData to image dict.
        NSMutableDictionary *image = [NSMutableDictionary dictionary];
        if (![input.mediaURL isEqual: @""] && input.mediaURL != nil) {
          // input has url
          image[@"url"] = input.mediaURL;
          image[@"allow_duplicate_url"] = input.allowDuplicateURLs ? @YES : @NO;
        } else if (input.mediaData != nil) {
          // input has image data
          NSString *encodedString = [input.mediaData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
          image[@"base64"] = encodedString;
        }
        
        // add crop, if exists, to image dict.
        if (!CGRectIsNull(((ClarifaiImage *)input).crop) && !CGRectIsEmpty(((ClarifaiImage *)input).crop)) {
          [image setObject:@[ @(((ClarifaiImage *)input).crop.origin.x),
                              @(((ClarifaiImage *)input).crop.origin.y),
                              @(((ClarifaiImage *)input).crop.size.width),
                              @(((ClarifaiImage *)input).crop.size.height) ] forKey:@"crop"];
        }
        
        data[@"image"] = image;
        
        // add concepts to data dict.
        if (input.concepts != nil && input.concepts.count != 0) {
          NSMutableArray *concepts = [NSMutableArray array];
          // init concepts
          for (ClarifaiConcept *concept in input.concepts) {
            NSMutableDictionary *conceptDict = [NSMutableDictionary dictionary];
            conceptDict[@"id"] = concept.conceptID;
            // can only be true or false when adding concepts with inputs.
            conceptDict[@"value"] = concept.score > 0 ? [NSNumber numberWithInt:1] : [NSNumber numberWithInt:0];
            [concepts addObject:conceptDict];
          }
          data[@"concepts"] = concepts;
        }
        
        inputEntry[@"data"] = data;
        [inputsArray addObject:inputEntry];
      }
    }
    
    NSDictionary *params = @{ @"inputs": inputsArray };
    [self.manager POST:apiURL
            parameters:params
               success:^(AFHTTPRequestOperation *op, id response) {
                 NSMutableArray *inputs = [NSMutableArray array];
                 NSArray *inputsResponse = response[@"inputs"];
                 for (NSDictionary *inputEntry in inputsResponse) {
                   [inputs addObject:[[ClarifaiInput alloc] initWithDictionary:inputEntry]];
                 }
                 completion(inputs, nil);
               } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                 if (op.response.statusCode >= 400) {
                   error = [self errorFromHttpResponse:op];
                 }
                 completion(nil, error);
               }];
  }];
}

- (void)addConcepts:(NSArray <ClarifaiConcept *> *)concepts toModelWithID:(NSString *)modelID completion:(ClarifaiModelCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSMutableArray *conceptsArray = [NSMutableArray array];
    for (ClarifaiConcept *concept in concepts) {
      NSMutableDictionary *conceptDict = [NSMutableDictionary dictionary];
      conceptDict[@"id"] = concept.conceptID;
      [conceptsArray addObject:conceptDict];
    }
    
    params[@"concepts"] = conceptsArray;
    params[@"action"] = @"merge_concepts";
    
    NSString *inputURLSuffix = [NSString stringWithFormat:@"/models/%@/output_info/data/concepts", modelID];
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:inputURLSuffix];
    [self.manager PATCH:apiURL
             parameters:params
                success:^(AFHTTPRequestOperation *op, id response) {
                  NSDictionary *status = response[@"status"];
                  long code = [status[@"code"] longValue];
                  if (code == 10000) {
                    ClarifaiModel *model = [[ClarifaiModel alloc] initWithDictionary:response[@"model"]];
                    completion(model, nil);
                  } else if (code == 21202) {
                    NSError *error = [[NSError alloc] initWithDomain:kErrorDomain
                                                                code:400
                                                            userInfo:@{@"description": status[@"description"],
                                                                           @"details": status[@"details"]}];
                    completion(nil, error);
                  }
                } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                  if (op.response.statusCode >= 400) {
                    error = [self errorFromHttpResponse:op];
                  }
                  completion(nil, error);
    }];
    
  }];
};

- (void)deleteConcepts:(NSArray <ClarifaiConcept *> *)concepts fromModelWithID:(NSString *)modelID completion:(ClarifaiModelCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSMutableArray *conceptsArray = [NSMutableArray array];
    for (ClarifaiConcept *concept in concepts) {
      NSMutableDictionary *conceptDict = [NSMutableDictionary dictionary];
      conceptDict[@"id"] = concept.conceptID;
      [conceptsArray addObject:conceptDict];
    }
    
    params[@"concepts"] = conceptsArray;
    params[@"action"] = @"delete_concepts";
    
    NSString *inputURLSuffix = [NSString stringWithFormat:@"/models/%@/output_info/data/concepts", modelID];
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:inputURLSuffix];
    [self.manager PATCH:apiURL
             parameters:params
                success:^(AFHTTPRequestOperation *op, id response) {
                  NSDictionary *status = response[@"status"];
                  long code = [status[@"code"] longValue];
                  if (code == 10000) {
                    ClarifaiModel *model = [[ClarifaiModel alloc] initWithDictionary:response[@"model"]];
                    completion(model, nil);
                  } else if (code == 21202) {
                    NSError *error = [[NSError alloc] initWithDomain:kErrorDomain
                                                                code:400
                                                            userInfo:@{@"description": status[@"description"],
                                                                       @"details": status[@"details"]}];
                    completion(nil, error);
                  }
                } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                  if (op.response.statusCode >= 400) {
                    error = [self errorFromHttpResponse:op];
                  }
                  completion(nil, error);
                }];
    
  }];
};

- (void)addConcepts:(NSArray <ClarifaiConcept *> *)concepts forInputWithID:(NSString *)inputID completion:(ClarifaiStoreInputCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    
    NSMutableDictionary *inputDict = [NSMutableDictionary dictionary];
    inputDict[@"id"] = inputID;
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSMutableArray *conceptsArray = [NSMutableArray array];
    for (ClarifaiConcept *concept in concepts) {
      NSMutableDictionary *conceptDict = [NSMutableDictionary dictionary];
      conceptDict[@"id"] = concept.conceptID;
      conceptDict[@"value"] = [NSNumber numberWithFloat:concept.score];
      [conceptsArray addObject:conceptDict];
    }
    
    params[@"concepts"] = conceptsArray;
    params[@"action"] = @"merge_concepts";
    
    NSString *inputURLSuffix = [NSString stringWithFormat:@"/inputs/%@/data/concepts", inputID];
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:inputURLSuffix];
    [self.manager PATCH:apiURL
             parameters:params
                success:^(AFHTTPRequestOperation *op, id response) {
                  completion([[ClarifaiInput alloc] initWithDictionary:response[@"input"]], nil);
                } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                  if (op.response.statusCode >= 400) {
                    error = [self errorFromHttpResponse:op];
                  }
                  completion(nil, error);
                }];
  }];
}

- (void)deleteConcepts:(NSArray <ClarifaiConcept *> *)concepts forInputWithID:(NSString *)inputID completion:(ClarifaiStoreInputCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    
    NSMutableDictionary *inputDict = [NSMutableDictionary dictionary];
    inputDict[@"id"] = inputID;
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSMutableArray *conceptsArray = [NSMutableArray array];
    for (ClarifaiConcept *concept in concepts) {
      NSMutableDictionary *conceptDict = [NSMutableDictionary dictionary];
      conceptDict[@"id"] = concept.conceptID;
      [conceptsArray addObject:conceptDict];
    }
    
    params[@"concepts"] = conceptsArray;
    params[@"action"] = @"delete_concepts";
    
    NSString *inputURLSuffix = [NSString stringWithFormat:@"/inputs/%@/data/concepts", inputID];
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:inputURLSuffix];
    [self.manager PATCH:apiURL
             parameters:params
                success:^(AFHTTPRequestOperation *op, id response) {
                  completion([[ClarifaiInput alloc] initWithDictionary:response[@"input"]], nil);
                } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                  if (op.response.statusCode >= 400) {
                    error = [self errorFromHttpResponse:op];
                  }
                  completion(nil, error);
                }];
  }];
}

- (void)getInputsOnPage:(int)page pageSize:(int)pageSize completion:(ClarifaiInputsCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/inputs"];
    [self.manager GET:apiURL
           parameters:@{ @"page": @(page), @"per_page": @(pageSize) }
              success:^(AFHTTPRequestOperation *op, id response) {
                NSMutableArray *inputs = [NSMutableArray array];
                NSArray *inputsResponse = response[@"inputs"];
                for (NSDictionary *input in inputsResponse) {
                  [inputs addObject:[[ClarifaiImage alloc] initWithDictionary:input]];
                }
                completion(inputs, nil);
              } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                if (op.response.statusCode >= 400) {
                  error = [self errorFromHttpResponse:op];
                }
                completion(nil, error);
              }];
  }];
}

- (void)getInput:(NSString *)inputID completion:(ClarifaiStoreInputCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *inputURLSuffix = [NSString stringWithFormat:@"/inputs/%@", inputID];
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:inputURLSuffix];
    [self.manager GET:apiURL
           parameters:nil
              success:^(AFHTTPRequestOperation *op, id response) {
                NSDictionary *inputResponse = response[@"input"];
                ClarifaiInput *input = [[ClarifaiInput alloc] initWithDictionary:inputResponse];
                completion(input, nil);
              } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                if (op.response.statusCode >= 400) {
                  error = [self errorFromHttpResponse:op];
                }
                completion(nil, error);
              }];
  }];
}

- (void)getInputsStatus:(ClarifaiInputsStatusCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, 0, 0, 0, error);
      return;
    }
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/inputs/status"];
    [self.manager GET:apiURL
           parameters:nil
              success:^(AFHTTPRequestOperation *op, id response) {
                NSDictionary *counts = response[@"counts"];
                int processed = [counts[@"processed"] intValue];
                int toProcess = [counts[@"to_process"] intValue];
                int errors = [counts[@"errors"] intValue];
                SafeRunBlock(completion, processed, toProcess, errors, nil);
              } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                if (op.response.statusCode >= 400) {
                  error = [self errorFromHttpResponse:op];
                }
                SafeRunBlock(completion, 0, 0, 0, nil);
              }];
  }];
}

- (void)deleteInput:(NSString *)inputID completion:(ClarifaiRequestCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, error);
      return;
    }
    NSString *endpoint = [NSString stringWithFormat:@"/inputs/%@", inputID];
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:endpoint];
    [self.manager DELETE:apiURL
              parameters:nil
                 success:^(AFHTTPRequestOperation *op, id response) {
                   completion(nil);
                 } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                   if (op.response.statusCode >= 400) {
                     error = [self errorFromHttpResponse:op];
                   }
                   completion(error);
                 }];
  }];
}

- (void)deleteAllInputs:(ClarifaiRequestCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, error);
      return;
    }
    NSString *endpoint = @"/inputs/";
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:endpoint];
    [self.manager DELETE:apiURL
              parameters:nil
                 success:^(AFHTTPRequestOperation *op, id response) {
                   completion(nil);
                 } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                   if (op.response.statusCode >= 400) {
                     error = [self errorFromHttpResponse:op];
                   }
                   completion(error);
                 }];
  }];
}

- (void)deleteInputsByIDList:(NSArray <ClarifaiInput *> *)inputs completion:(ClarifaiRequestCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, error);
      return;
    }
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSMutableArray *inputsArray = [NSMutableArray array];
    for (ClarifaiInput *input in inputs) {
      NSMutableDictionary *inputDict = [NSMutableDictionary dictionary];
      inputDict[@"id"] = input.inputID;
      [inputsArray addObject:inputDict];
    }
    
    params[@"inputs"] = inputsArray;
    params[@"action"] = @"delete_inputs";
    
    NSString *inputURLSuffix = @"/inputs/";
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:inputURLSuffix];
    [self.manager PATCH:apiURL
             parameters:params
                success:^(AFHTTPRequestOperation *op, id response) {
                  completion(nil);
                } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                  if (op.response.statusCode >= 400) {
                    error = [self errorFromHttpResponse:op];
                  }
                  completion(error);
                }];
  }];
}

#pragma mark - concepts

- (void)getConceptsOnPage:(int)page pageSize:(int)pageSize completion:(ClarifaiSearchConceptCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/concepts"];
    [self.manager GET:apiURL
           parameters:@{ @"page": @(page), @"per_page": @(pageSize) }
              success:^(AFHTTPRequestOperation *op, id response) {
                NSMutableArray *inputs = [NSMutableArray array];
                NSArray *conceptsResponse = response[@"concepts"];
                for (NSDictionary *concept in conceptsResponse) {
                  NSDictionary *conceptDict = @{@"concept":concept};
                  [inputs addObject:[[ClarifaiConcept alloc] initWithDictionary:conceptDict]];
                }
                completion(inputs, nil);
              } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                if (op.response.statusCode >= 400) {
                  error = [self errorFromHttpResponse:op];
                }
                completion(nil, error);
              }];
  }];
  
}

- (void)getConcept:(NSString *)conceptID completion:(ClarifaiStoreConceptCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *inputURLSuffix = [NSString stringWithFormat:@"/concepts/%@", conceptID];
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:inputURLSuffix];
    [self.manager GET:apiURL
           parameters:nil
              success:^(AFHTTPRequestOperation *op, id response) {
                ClarifaiConcept *concept = [[ClarifaiConcept alloc] initWithDictionary:response[@"concept"]];
                completion(concept, nil);
              } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                if (op.response.statusCode >= 400) {
                  error = [self errorFromHttpResponse:op];
                }
                completion(nil, error);
              }];
  }];
}

- (void)addConcepts:(NSArray <ClarifaiConcept *> *)concepts completion:(ClarifaiConceptsCompletion)completion {
  
  NSMutableArray *conceptsArray = [NSMutableArray array];
  
  for (ClarifaiConcept *concept in concepts) {
    NSMutableDictionary *conceptDict = [NSMutableDictionary dictionary];
    conceptDict[@"id"] = concept.conceptID;
    conceptDict[@"name"] = concept.conceptID;
    [conceptsArray addObject:conceptDict];
  }
  
  NSDictionary *params = @{ @"concepts": conceptsArray };
  
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/concepts/"];
    [self.manager POST:apiURL
            parameters:params
               success:^(AFHTTPRequestOperation *op, id response) {
                 NSMutableArray *conceptsArray = [NSMutableArray array];
                 NSArray *conceptsResponse = response[@"concepts"];
                 for (NSDictionary *concept in conceptsResponse) {
                   [conceptsArray addObject:[[ClarifaiConcept alloc] initWithDictionary:concept]];
                 }
                 completion(conceptsArray, nil);
               } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                 if (op.response.statusCode >= 400) {
                   error = [self errorFromHttpResponse:op];
                 }
                 completion(nil, error);
               }];
  }];
}

#pragma mark - Search

- (NSDictionary *)formatItemForSearch:(ClarifaiSearchTerm *)searchTerm {
  if ([searchTerm.searchItem isKindOfClass:[ClarifaiImage class]]) {
    ClarifaiImage *image = (ClarifaiImage *)searchTerm.searchItem;
    if (image.inputID) {
      if (searchTerm.isInput) {
        return @{@"input": @{@"id": image.inputID, @"data": @{@"image": @{@"crop": @[@(image.crop.origin.x),
                                                                                     @(image.crop.origin.y),
                                                                                     @(image.crop.size.width),
                                                                                     @(image.crop.size.height)]}}}};
      } else {
        return  @{@"output": @{@"input": @{@"id": image.inputID, @"data": @{@"image": @{@"crop": @[@(image.crop.origin.x),
                                                                                                   @(image.crop.origin.y),
                                                                                                   @(image.crop.size.width),
                                                                                                   @(image.crop.size.height)]}}}}};
      }
    } else if (image.mediaURL) {
      if (searchTerm.isInput) {
        return @{@"input": @{@"data": @{@"image": @{@"url": image.mediaURL }}}};
      } else {
        return @{@"output": @{@"input": @{@"data": @{@"image": @{@"url": image.mediaURL }}}}};
      }
    } else if (image.mediaData) {
      if (searchTerm.isInput) {
        return @{@"input": @{@"data": @{@"image": @{@"base64": [image.mediaData
                                                                base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength] }}}};
      } else {
        return @{@"output": @{@"input": @{@"data": @{@"image": @{@"base64": [image.mediaData
                                                                             base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength] }}}}};
      }
    }
  } else if ([searchTerm.searchItem isKindOfClass:[ClarifaiConcept class]]) {
    ClarifaiConcept *concept = (ClarifaiConcept *)searchTerm.searchItem;
    if (concept.conceptID) {
      if (searchTerm.isInput) {
        return @{@"input": @{@"data": @{@"concepts": @[ @{@"id": concept.conceptID, @"value": @(YES)}]}}};
      } else {
        return @{@"output": @{@"data": @{@"concepts": @[ @{@"id": concept.conceptID, @"value": @(YES)}]}}};
      }
    } else {
      if (searchTerm.isInput) {
        return @{@"input": @{@"data": @{@"concepts": @[ @{@"name": concept.conceptName, @"value": @(YES)}]}}};
      } else {
        return @{@"output": @{@"data": @{@"concepts": @[ @{@"name": concept.conceptName, @"value": @(YES)}]}}};
      }
    }

  }
  return nil;
}

- (void)search:(NSArray <ClarifaiSearchTerm *> *)searchTerms
          page:(NSNumber *)page
       perPage:(NSNumber *)perPage
    completion:(ClarifaiSearchCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      completion(nil, error);
    } else {
      NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/searches"];
      
      NSMutableArray *ands = [NSMutableArray array];
      
      for (ClarifaiSearchTerm *term in searchTerms) {
        NSDictionary *termBlock = [self formatItemForSearch:term];
        [ands addObject: termBlock];
      }
      
      NSMutableDictionary *query = [NSMutableDictionary dictionary];
      query[@"ands"] = ands;
      
      NSDictionary *pagination = @{@"page": page, @"per_page": perPage};

      [self.manager POST:apiURL parameters:@{@"query": query, @"pagination":pagination} success:^(AFHTTPRequestOperation *operation, NSDictionary *response) {
        NSArray *hits = response[@"hits"];
        NSArray<ClarifaiSearchResult *> *searchResults = [hits map:^(NSDictionary *hit) {
          return [[ClarifaiSearchResult alloc] initWithDictionary:hit];
        }];
        completion(searchResults, nil);
      } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        completion(nil, error);
      }];
    }
  }];
}

#pragma mark - Model

- (void)getModels:(int)page resultsPerPage:(int)resultsPerPage completion:(ClarifaiModelsCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/models"];
    [self.manager GET:apiURL parameters:@{@"page": @(page), @"per_page": @(resultsPerPage)} success:^(AFHTTPRequestOperation *operation, id responseObject) {
      NSMutableArray *clarifaiModels = [NSMutableArray array];
      NSArray *models = responseObject[@"models"];
      for (NSDictionary *model in models) {
        ClarifaiModel *clarifaiModel = [[ClarifaiModel alloc] initWithDictionary:model];
        clarifaiModel.app = self;
        [clarifaiModels addObject:clarifaiModel];
      }
      completion(clarifaiModels, nil);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
      completion(nil, error);
    }];
  }];
}

- (void)getModelByID:(NSString *)modelID completion:(ClarifaiModelCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [NSString stringWithFormat:@"%@/models/%@/output_info", kApiBaseUrl, modelID];
    [self.manager GET:apiURL parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
      ClarifaiModel *model;
      model = [[ClarifaiModel alloc] initWithDictionary:responseObject[@"model"]];
      model.app = self;
      completion(model, nil);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
      completion(nil, error);
    }];
  }];
}

- (void)getModelByName:(NSString *)modelName completion:(ClarifaiModelCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    [self searchForModelByName:modelName modelType:ClarifaiModelTypeConcept completion:^(NSArray<ClarifaiModel *> *models, NSError *error) {
      if (error) {
        SafeRunBlock(completion, nil, error);
      }
      if (models.count > 0) {
        SafeRunBlock(completion, models[0], nil);
      } else {
        SafeRunBlock(completion, nil, nil);
      }
    }];
  }];
}


- (void)listVersionsForModel:(NSString *)modelID
                        page:(int)page
              resultsPerPage:(int)resultsPerPage
                  completion:(ClarifaiModelVersionsCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [NSString stringWithFormat:@"%@/models/%@/versions?page=%i&per_page=%i", kApiBaseUrl, modelID, page, resultsPerPage];
    [self.manager GET:apiURL
           parameters:nil
              success:^(AFHTTPRequestOperation *operation, id responseObject) {
      NSMutableArray *versions = [NSMutableArray array];
      NSArray *versionDicts = responseObject[@"model_versions"];
      for (NSDictionary *versionDict in versionDicts) {
        ClarifaiModelVersion *version = [[ClarifaiModelVersion alloc] initWithDictionary:versionDict];
        [versions addObject:version];
      }
      completion(versions, nil);
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
      completion(nil, error);
    }];
  }];
}

- (void)getVersionForModel:(NSString *)modelID
                 versionID:(NSString *)versionID
                completion:(ClarifaiModelVersionCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [NSString stringWithFormat:@"%@/models/%@/versions/%@/", kApiBaseUrl, modelID, versionID];
    [self.manager GET:apiURL
           parameters:nil
              success:^(AFHTTPRequestOperation *operation, id responseObject) {
                ClarifaiModelVersion *version = [[ClarifaiModelVersion alloc] initWithDictionary:responseObject[@"model_version"]];
                completion(version, nil);
              } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
                completion(nil, error);
              }];
  }];
}

- (void)deleteVersionForModel:(NSString *)modelID
                    versionID:(NSString *)versionID
                   completion:(ClarifaiRequestCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, error);
      return;
    }
    NSString *apiURL = [NSString stringWithFormat:@"%@/models/%@/versions/%@/", kApiBaseUrl, modelID, versionID];
    [self.manager DELETE:apiURL
              parameters:nil
                 success:^(AFHTTPRequestOperation *operation, id responseObject) {
                   completion(nil);
                 } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
                   completion(error);
                 }];
  }];
}

- (void)listTrainingInputsForModel:(NSString *)modelID
                        page:(int)page
              resultsPerPage:(int)resultsPerPage
                  completion:(ClarifaiInputsCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [NSString stringWithFormat:@"%@/models/%@/inputs?page=%i&per_page=%i", kApiBaseUrl, modelID, page, resultsPerPage];
    [self.manager GET:apiURL
           parameters:nil
              success:^(AFHTTPRequestOperation *operation, id responseObject) {
                NSMutableArray *inputs = [NSMutableArray array];
                NSArray *inputDicts = responseObject[@"inputs"];
                for (NSDictionary *inputDict in inputDicts) {
                  ClarifaiInput *input = [[ClarifaiInput alloc] initWithDictionary:inputDict];
                  [inputs addObject:input];
                }
                completion(inputs, nil);
              } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
                completion(nil, error);
              }];
  }];
}

- (void)listTrainingInputsForModel:(NSString *)modelID
                           version:(NSString *)versionID
                              page:(int)page
                    resultsPerPage:(int)resultsPerPage
                        completion:(ClarifaiInputsCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [NSString stringWithFormat:@"%@/models/%@/versions/%@/inputs?page=%i&per_page=%i", kApiBaseUrl, modelID, versionID, page, resultsPerPage];
    [self.manager GET:apiURL
           parameters:nil
              success:^(AFHTTPRequestOperation *operation, id responseObject) {
                NSMutableArray *inputs = [NSMutableArray array];
                NSArray *inputDicts = responseObject[@"inputs"];
                for (NSDictionary *inputDict in inputDicts) {
                  ClarifaiInput *input = [[ClarifaiInput alloc] initWithDictionary:inputDict];
                  [inputs addObject:input];
                }
                completion(inputs, nil);
              } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
                completion(nil, error);
              }];
  }];
}

- (void)searchForModelByName:(NSString *)modelName
                   modelType:(ClarifaiModelType)modelType
                  completion:(ClarifaiModelsCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/models/searches"];
    NSDictionary *params = @{@"model_query": @{@"name": modelName, @"type": _modelTypes[@(modelType)]}};
    [self.manager POST:apiURL parameters:params success:^(AFHTTPRequestOperation *operation, id responseObject) {
      NSMutableArray *clarifaiModels = [NSMutableArray array];
      NSArray *models = responseObject[@"models"];
      for (NSDictionary *model in models) {
        ClarifaiModel *clarifaiModel = [[ClarifaiModel alloc] initWithDictionary:model];
        clarifaiModel.app = self;
        [clarifaiModels addObject:clarifaiModel];
      }
      completion(clarifaiModels, nil);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
      completion(nil, error);
    }];
  }];
}

- (void)createModel:(NSArray *)concepts
               name:(NSString *)modelName
  conceptsMutuallyExclusive:(BOOL)conceptsMutuallyExclusive
  closedEnvironment:(BOOL)closedEnvironment
         completion:(ClarifaiModelCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    
    NSArray *conceptsArray = [concepts map:^(id concept) {
      if ([concept isKindOfClass:[NSString class]]) {
        return @{@"id": (NSString *)concept};
      } else {
        ClarifaiConcept *actualConcept = (ClarifaiConcept *)concept;
        return @{@"id": actualConcept.conceptID};
      }
    }];
    
    NSDictionary *model =
    @{
      @"model": @{
          @"name": modelName,
          @"output_info": @{
              @"data": @{
                  @"concepts": conceptsArray
                  },
              @"output_config": @{
                  @"concepts_mutually_exclusive": conceptsMutuallyExclusive ? @YES : @NO,
                  @"closed_environment": closedEnvironment ? @YES : @NO
                  }
              }
          }
      };
    
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:@"/models"];
    [self.manager POST:apiURL parameters:model success:^(AFHTTPRequestOperation *operation, id responseObject) {
      ClarifaiModel *model = [[ClarifaiModel alloc] initWithDictionary:responseObject[@"model"]];
      model.app = self;
      completion(model, nil);
    } failure:^(AFHTTPRequestOperation * operation, NSError *error) {
      completion(nil, error);
    }];
  }];
}

- (void)deleteModel:(NSString *)modelID completion:(ClarifaiRequestCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, error);
      return;
    }
    NSString *endpoint = [NSString stringWithFormat:@"/models/%@", modelID];
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:endpoint];
    [self.manager DELETE:apiURL
              parameters:nil
                 success:^(AFHTTPRequestOperation *op, id response) {
                   completion(nil);
                 } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                   if (op.response.statusCode >= 400) {
                     error = [self errorFromHttpResponse:op];
                   }
                   completion(error);
                 }];
  }];
}

- (void)deleteAllModels:(ClarifaiRequestCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, error);
      return;
    }
    NSString *endpoint = @"/models/";
    NSString *apiURL = [kApiBaseUrl stringByAppendingString:endpoint];
    [self.manager DELETE:apiURL
              parameters:nil
                 success:^(AFHTTPRequestOperation *op, id response) {
                   completion(nil);
                 } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                   if (op.response.statusCode >= 400) {
                     error = [self errorFromHttpResponse:op];
                   }
                   completion(error);
                 }];
  }];
}


- (void)getOutputInfoForModel:(NSString *)modelID completion:(ClarifaiModelCompletion)completion {
  [self ensureValidAccessToken:^(NSError *error) {
    if (error) {
      SafeRunBlock(completion, nil, error);
      return;
    }
    NSString *apiURL = [NSString stringWithFormat:@"%@/models/%@/output_info", kApiBaseUrl, modelID];
    [self.manager GET:apiURL
           parameters:nil
              success:^(AFHTTPRequestOperation *operation, id responseObject) {
      ClarifaiModel *model = [[ClarifaiModel alloc] initWithDictionary:responseObject[@"model"]];
      completion(model, nil);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
      completion(nil, error);
    }];
  }];
}

#pragma mark - Access Token Management

- (void)setAccessToken:(NSString *)accessToken {
  _accessToken = accessToken;
  NSString *value = [NSString stringWithFormat:@"Bearer %@", self.accessToken];
  [self.manager.requestSerializer setValue:value forHTTPHeaderField:@"Authorization"];
  [self.manager.requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
}

- (void)ensureValidAccessToken:(void (^)(NSError *error))handler {
  if (self.accessToken && self.accessTokenExpiration &&
      [self.accessTokenExpiration timeIntervalSinceNow] >= kMinTokenLifetime) {
    handler(nil);  // We have a valid access token.
  } else {
    self.authenticating = YES;
    // Send a request to the auth endpoint. See: https://developer.clarifai.com/docs/auth.
    NSString *clientSecret = [NSString stringWithFormat:@"%@:%@", self.appID, self.appSecret];
    NSData *clientSecretData = [clientSecret dataUsingEncoding:NSUTF8StringEncoding];
    NSString *clientSecretBase64 = [clientSecretData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    [self.manager.requestSerializer setValue:[@"Basic " stringByAppendingString:clientSecretBase64] forHTTPHeaderField:@"Authorization"];
    [self.manager POST:[kApiBaseUrl stringByAppendingString:@"/token"]
            parameters:nil
               success:^(AFHTTPRequestOperation *op, id response) {
                 ClarifaiAccessTokenResponse *res = [[ClarifaiAccessTokenResponse alloc]
                                                     initWithDictionary:response];
                 [self saveAccessToken:res];
                 self.authenticating = NO;
                 handler(nil);
               } failure:^(AFHTTPRequestOperation *op, NSError *error) {
                 if (op.response.statusCode >= 400) {
                   error = [self errorFromHttpResponse:op];
                 }
                 self.authenticating = NO;
                 handler(error);
               }];
  }
}

- (void)loadAccessToken {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if (![self.appID isEqualToString:[defaults valueForKey:kKeyAppID]]) {
    [self invalidateAccessToken];
  } else {
    self.accessToken = [defaults valueForKey:kKeyAccessToken];
    self.accessTokenExpiration = [defaults valueForKey:kKeyAccessTokenExpiration];
  }
}

- (void)saveAccessToken:(ClarifaiAccessTokenResponse *)response {
  if (response.accessToken) {
    NSDate *expiration = [NSDate dateWithTimeIntervalSinceNow:response.expiresIn];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:response.accessToken forKey:kKeyAccessToken];
    [defaults setObject:expiration forKey:kKeyAccessTokenExpiration];
    [defaults setObject:self.appID forKey:kKeyAppID];
    [defaults synchronize];
    self.accessToken = response.accessToken;
    self.accessTokenExpiration = expiration;
  }
}

- (void)invalidateAccessToken {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObjectForKey:kKeyAccessToken];
  [defaults removeObjectForKey:kKeyAccessTokenExpiration];
  [defaults removeObjectForKey:kKeyAppID];
  [defaults synchronize];
  self.accessToken = nil;
  self.accessTokenExpiration = nil;
}

#pragma mark -

- (NSError *)errorFromHttpResponse:(AFHTTPRequestOperation *)op {
  NSString *desc;
  if (op.responseString) {
    desc = op.responseString;
  } else {
    desc = [NSString stringWithFormat:@"HTTP Status %d", (int)op.response.statusCode];
  }
  NSString *url = [op.request.URL absoluteString];
  return [[NSError alloc] initWithDomain:kErrorDomain
                                    code:op.response.statusCode
                                userInfo:@{@"description": desc, @"url": url}];
}


@end
