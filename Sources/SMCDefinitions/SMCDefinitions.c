// Materialize this Clang target for SwiftPM's Xcode-based universal builds.
// A header-only target can leave SMCDefinitions_Module.o missing at link time.
// Including the header also checks the AppleSMC ABI assertions for each arch.
#include "SMCDefinitions.h"
