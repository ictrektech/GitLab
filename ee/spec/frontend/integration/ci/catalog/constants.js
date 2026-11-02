// Raised by `Resolvers::Ci::Catalog::ResourceResolver` for a resource the user cannot see,
// such as an unpublished one.
export const RESOURCE_NOT_AVAILABLE_ERROR =
  "The resource that you are attempting to access does not exist or you don't have permission to perform this action";

// The two releases the fixture generator tags; `LATEST_VERSION` is the one selected by default.
export const LATEST_VERSION = '2.0.0';
export const PREVIOUS_VERSION = '1.0.0';
