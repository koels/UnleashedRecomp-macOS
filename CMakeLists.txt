cmake_minimum_required (VERSION 3.20)

if(NOT DEFINED ENV{VCPKG_ROOT})
    message(FATAL_ERROR "VCPKG_ROOT is not defined!")
endif()

set(UNLEASHED_RECOMP_THIRDPARTY_ROOT ${CMAKE_SOURCE_DIR}/thirdparty)
set(UNLEASHED_RECOMP_TOOLS_ROOT ${CMAKE_SOURCE_DIR}/tools)
set(CMAKE_CXX_STANDARD 20)
set(BUILD_SHARED_LIBS OFF)

# Enable Hot Reload for MSVC compilers if supported.
if (POLICY CMP0141)
  cmake_policy(SET CMP0141 NEW)
  set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT "$<IF:$<AND:$<C_COMPILER_ID:MSVC>,$<CXX_COMPILER_ID:MSVC>>,$<$<CONFIG:Debug,RelWithDebInfo>:EditAndContinue>,$<$<CONFIG:Debug,RelWithDebInfo>:ProgramDatabase>>")
endif()

set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

project("UnleashedRecomp-ALL")

# macOS app identity and updates. Leave the Sparkle values empty to build without update checks.
set(UNLEASHED_RECOMP_BUNDLE_ID "io.github.koels.UnleashedRecomp" CACHE STRING "macOS bundle identifier")
set(UNLEASHED_RECOMP_SPARKLE_FEED_URL "" CACHE STRING "Sparkle appcast URL")
# Public half of the key stored in the keychain under the "unleashed-recomp-macos" account.
set(UNLEASHED_RECOMP_SPARKLE_PUBLIC_KEY "Jt6cOSfJptp74KNHgW8ZKea+odZg7rn3TpJ1l5xlTaQ=" CACHE STRING "Sparkle EdDSA public key (from generate_keys)")

if (APPLE)
    enable_language(OBJC OBJCXX)
endif()

if (CMAKE_OSX_ARCHITECTURES)
    set(UNLEASHED_RECOMP_ARCHITECTURE ${CMAKE_OSX_ARCHITECTURES})
elseif(CMAKE_SYSTEM_PROCESSOR)
    set(UNLEASHED_RECOMP_ARCHITECTURE ${CMAKE_SYSTEM_PROCESSOR})
else()
    set(UNLEASHED_RECOMP_ARCHITECTURE ${CMAKE_HOST_SYSTEM_PROCESSOR})
endif()
string(TOLOWER "${UNLEASHED_RECOMP_ARCHITECTURE}" UNLEASHED_RECOMP_ARCHITECTURE)
message(STATUS "Detected architecture: ${UNLEASHED_RECOMP_ARCHITECTURE}")

if (UNLEASHED_RECOMP_ARCHITECTURE STREQUAL "x86_64" OR UNLEASHED_RECOMP_ARCHITECTURE STREQUAL "amd64")
    # Target Sandy Bridge for all projects
    add_compile_options(
        -march=sandybridge
    )
endif()

# macOS fixes to submodules live as patches in thirdparty-patches/ and are applied once here.
foreach(PATCH_NAME SDL imgui plume)
    set(PATCH_FILE "${CMAKE_SOURCE_DIR}/thirdparty-patches/${PATCH_NAME}.patch")
    set(PATCH_DIR "${UNLEASHED_RECOMP_THIRDPARTY_ROOT}/${PATCH_NAME}")

    execute_process(COMMAND git apply --reverse --check "${PATCH_FILE}"
        WORKING_DIRECTORY "${PATCH_DIR}" RESULT_VARIABLE PATCH_ALREADY_APPLIED OUTPUT_QUIET ERROR_QUIET)

    if (NOT PATCH_ALREADY_APPLIED EQUAL 0)
        execute_process(COMMAND git apply "${PATCH_FILE}"
            WORKING_DIRECTORY "${PATCH_DIR}" RESULT_VARIABLE PATCH_RESULT)

        if (NOT PATCH_RESULT EQUAL 0)
            message(FATAL_ERROR "Failed to apply ${PATCH_FILE}. Run 'git submodule update' to reset ${PATCH_DIR} and configure again.")
        endif()

        message(STATUS "Applied ${PATCH_NAME}.patch")
    endif()
endforeach()

add_subdirectory(${UNLEASHED_RECOMP_THIRDPARTY_ROOT})
add_subdirectory(${UNLEASHED_RECOMP_TOOLS_ROOT})

# Include sub-projects.
add_subdirectory("UnleashedRecompLib")
add_subdirectory("UnleashedRecomp")
