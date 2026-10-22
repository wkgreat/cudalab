cmake_minimum_required(VERSION 3.24)

# ---------------------------------------------------------------------------
# env.json - the remaining machine-specific paths
#
# It holds only what pixi cannot supply: the CUDA toolkit root, the MSVC
# environment script and the Windows SDK UCRT include directory (see pixi.toml -
# cmake, ninja, clangd and, on Linux, the CUDA toolkit all come from pixi).
# scripts/sync-env.ps1 writes it from detection. On Linux nothing is needed at
# all: nvcc and g++ are on PATH inside the pixi environment.
#
# The GPU's compute capability is no longer stored here: the architecture
# defaults to CMake's own "native" (CMake 3.24+), so the value follows the GPU
# that is actually present. An explicit cuda.arch in env.json still wins, for a
# machine with several GPUs or a cross build.
#
# This runs before project() on purpose: see the note on the cache entry below.
# ---------------------------------------------------------------------------
set(CUDALAB_CUDA_ARCH "native")
set(CUDALAB_CUDA_ROOT "")
set(CUDALAB_ENV_FILE "${CMAKE_CURRENT_SOURCE_DIR}/env.json")

if(EXISTS "${CUDALAB_ENV_FILE}")
    file(READ "${CUDALAB_ENV_FILE}" cudalab_env_json)

    # Optional: pin the architecture instead of letting CMake detect it.
    string(JSON cudalab_arch_value ERROR_VARIABLE cudalab_arch_error
        GET "${cudalab_env_json}" cuda arch)
    if(NOT cudalab_arch_error AND cudalab_arch_value)
        set(CUDALAB_CUDA_ARCH "${cudalab_arch_value}")
    endif()

    string(JSON cudalab_root_value ERROR_VARIABLE cudalab_root_error
        GET "${cudalab_env_json}" cuda root)
    if(NOT cudalab_root_error AND cudalab_root_value AND EXISTS "${cudalab_root_value}")
        set(CUDALAB_CUDA_ROOT "${cudalab_root_value}")
    endif()
endif()

# vcpkg - the package manager behind vcpkg.json, which supplies Catch2, fmt and
# OpenCL. The vcpkg program is not managed by pixi: these are the system's own
# installations, tried in order until one has the CMake toolchain file:
#
#   1. vcpkg.root in env.json (explicit, machine-specific override)
#   2. the VCPKG_ROOT environment variable (vcpkg's own convention)
#   3. a vcpkg executable on PATH
#   4. on Windows, C:/vcpkg
#   5. on Windows, the copy bundled with Visual Studio
#
# Pointing CMake at the toolchain before project() puts vcpkg into manifest
# mode: it reads vcpkg.json and installs the declared ports into
# <build>/vcpkg_installed. A -DCMAKE_TOOLCHAIN_FILE=... on the command line
# still wins, and a missing vcpkg installation just builds without it.
set(CUDALAB_VCPKG_ROOT "")
set(cudalab_vcpkg_candidates "")

if(EXISTS "${CUDALAB_ENV_FILE}")
    string(JSON cudalab_vcpkg_root_value ERROR_VARIABLE cudalab_vcpkg_root_error
        GET "${cudalab_env_json}" vcpkg root)
    if(NOT cudalab_vcpkg_root_error AND cudalab_vcpkg_root_value)
        list(APPEND cudalab_vcpkg_candidates "${cudalab_vcpkg_root_value}")
    endif()
endif()

if(DEFINED ENV{VCPKG_ROOT} AND "$ENV{VCPKG_ROOT}")
    list(APPEND cudalab_vcpkg_candidates "$ENV{VCPKG_ROOT}")
endif()

find_program(CUDALAB_VCPKG_EXECUTABLE NAMES vcpkg)
if(CUDALAB_VCPKG_EXECUTABLE)
    # Resolve symlinks so /usr/local/bin/vcpkg still yields the real root.
    file(REAL_PATH "${CUDALAB_VCPKG_EXECUTABLE}" cudalab_vcpkg_exe_real)
    get_filename_component(cudalab_vcpkg_from_path "${cudalab_vcpkg_exe_real}" DIRECTORY)
    list(APPEND cudalab_vcpkg_candidates "${cudalab_vcpkg_from_path}")
endif()

if(WIN32)
    list(APPEND cudalab_vcpkg_candidates "C:/vcpkg")

    # Visual Studio ships a vcpkg bundle; vswhere is the supported way to find
    # the installation that has the C++ toolset.
    find_program(CUDALAB_VSWHERE_EXECUTABLE NAMES vswhere.exe
        HINTS "C:/Program Files (x86)/Microsoft Visual Studio/Installer"
              "C:/Program Files/Microsoft Visual Studio/Installer")
    if(CUDALAB_VSWHERE_EXECUTABLE)
        execute_process(
            COMMAND "${CUDALAB_VSWHERE_EXECUTABLE}" -latest -products *
                -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64
                -property installationPath
            OUTPUT_VARIABLE cudalab_vs_path
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET)
        if(cudalab_vs_path)
            file(TO_CMAKE_PATH "${cudalab_vs_path}" cudalab_vs_path)
            list(APPEND cudalab_vcpkg_candidates "${cudalab_vs_path}/VC/vcpkg")
        endif()
    endif()
endif()

foreach(cudalab_vcpkg_candidate IN LISTS cudalab_vcpkg_candidates)
    if(NOT CUDALAB_VCPKG_ROOT AND
       EXISTS "${cudalab_vcpkg_candidate}/scripts/buildsystems/vcpkg.cmake")
        set(CUDALAB_VCPKG_ROOT "${cudalab_vcpkg_candidate}")
    endif()
endforeach()

# Build trees configured while vcpkg lived in the repository's .vcpkg/ keep that
# toolchain in their cache; replace it so they follow the detected installation.
set(cudalab_vcpkg_stale FALSE)
if(CMAKE_TOOLCHAIN_FILE MATCHES "[\\\\/]\\.vcpkg[\\\\/]")
    set(cudalab_vcpkg_stale TRUE)
endif()

if(CUDALAB_VCPKG_ROOT AND (NOT CMAKE_TOOLCHAIN_FILE OR cudalab_vcpkg_stale))
    set(CMAKE_TOOLCHAIN_FILE
        "${CUDALAB_VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
        CACHE FILEPATH "vcpkg toolchain file" FORCE)
    message(STATUS "cudalab: vcpkg -> ${CUDALAB_VCPKG_ROOT}")
elseif(NOT CUDALAB_VCPKG_ROOT)
    message(STATUS "cudalab: no vcpkg installation found (set VCPKG_ROOT, put vcpkg on PATH, or install Visual Studio's vcpkg); building without vcpkg")
endif()

# The CUDA compiler search only ever looks on PATH, but a toolkit installed
# under /usr/local/cuda keeps nvcc in a bin/ directory that is frequently not on
# it. env.json names the root, so point CMake at the nvcc inside it. Like the
# architecture below this must happen before project(), and a command-line
# -DCMAKE_CUDA_COMPILER=... still wins because setting a cache entry does not
# overwrite an existing one.
if(CUDALAB_CUDA_ROOT AND NOT DEFINED CMAKE_CUDA_COMPILER)
    if(WIN32)
        set(cudalab_nvcc "${CUDALAB_CUDA_ROOT}/bin/nvcc.exe")
    else()
        set(cudalab_nvcc "${CUDALAB_CUDA_ROOT}/bin/nvcc")
    endif()
    if(EXISTS "${cudalab_nvcc}")
        set(CMAKE_CUDA_COMPILER "${cudalab_nvcc}" CACHE FILEPATH "CUDA compiler")
    endif()
endif()

# This has to be set BEFORE project(). Enabling the CUDA language installs its
# own default for this cache entry, so a later `if(NOT DEFINED ...)` never fires
# and silently builds for the wrong architecture. Setting a cache entry does not
# overwrite an existing one, so an explicit -DCMAKE_CUDA_ARCHITECTURES=... on the
# command line still wins.
set(CMAKE_CUDA_ARCHITECTURES "${CUDALAB_CUDA_ARCH}" CACHE STRING "CUDA architectures to build for")

project(cudalab
    VERSION 1.0.0
    DESCRIPTION "CUDA lab - one executable target per demo"
    LANGUAGES CXX CUDA)

if(CUDALAB_CUDA_ROOT)
    set(CUDAToolkit_ROOT "${CUDALAB_CUDA_ROOT}")
    message(STATUS "cudalab: env.json -> CUDA arch ${CUDALAB_CUDA_ARCH}, toolkit ${CUDALAB_CUDA_ROOT}")
else()
    message(STATUS "cudalab: env.json missing or incomplete, using CUDA arch ${CUDALAB_CUDA_ARCH} (run scripts/sync-env.ps1)")
endif()

# Provides the imported CUDA::cudart target used below. The CUDA language
# support alone does not define it.
find_package(CUDAToolkit REQUIRED)

# Provides the imported OpenCL::OpenCL target used by demos that ship a .cl
# kernel. OpenCL is declared in vcpkg.json; that port builds the Khronos
# OpenCL SDK (headers + ICD loader) and its config package exposes
# OpenCL::OpenCL, which transitively carries the CL/ header include path. The
# CONFIG form is the package's documented lookup - CUDALAB_CUDA_ROOT's nvcc
# logic has already been resolved above, and unlike the CUDA toolkit OpenCL is
# a vcpkg dependency rather than a machine path in env.json.
find_package(OpenCL CONFIG REQUIRED)

# Provides the imported fmt::fmt target demos link when they use fmt for
# formatting. fmt is declared in vcpkg.json like OpenCL; its config package
# exports fmt::fmt.
find_package(fmt CONFIG REQUIRED)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

# Emit compile_commands.json for Ninja/Makefile builds so clangd and other
# tooling can see exactly how each file is compiled.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
endif()


# ---------------------------------------------------------------------------
# Compile settings shared by the shared library and every demo
# ---------------------------------------------------------------------------
function(cudalab_configure_target target has_cuda has_opencl)
    if(MSVC)
        # MSVC (Windows) needs its own spellings: gcc/clang reject /utf-8, /Zi
        # and -Xcompiler=/utf-8 outright.
        target_compile_options(${target} PRIVATE
            # CUDA 13 headers contain non-ASCII bytes; without /utf-8 MSVC
            # reports C4819 on a CJK code page and the console fills with
            # warnings.
            $<$<COMPILE_LANGUAGE:CXX>:/utf-8>
            $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=/utf-8>
            # CUDA 13's CCCL headers require the standard conforming
            # preprocessor; the traditional one is a hard #error.
            $<$<COMPILE_LANGUAGE:CXX>:/Zc:preprocessor>
            $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=/Zc:preprocessor>
            # Keep line information so a profiler can map SASS back to source.
            # Only for non-Debug builds: -G already implies line info and ptxas
            # rejects both.
            $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<NOT:$<CONFIG:Debug>>>:-lineinfo>
            # Device-side debug information in Debug builds only.
            $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<CONFIG:Debug>>:-G>
            $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<CONFIG:Debug>>:-g>
            $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<CONFIG:Debug>>:-Xcompiler=/Zi>
            $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<CONFIG:Debug>>:/Zi>)

        set_target_properties(${target} PROPERTIES
            MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
    else()
        # gcc/clang spellings. -Xcompiler keeps the flag on the host compiler
        # side of nvcc.
        target_compile_options(${target} PRIVATE
            $<$<COMPILE_LANGUAGE:CXX>:-finput-charset=UTF-8>
            $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=-finput-charset=UTF-8>
            # Keep line information so a profiler can map SASS back to source.
            # Only for non-Debug builds: -G already implies line info and ptxas
            # rejects both.
            $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<NOT:$<CONFIG:Debug>>>:-lineinfo>
            # Device-side debug information in Debug builds only.
            $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<CONFIG:Debug>>:-G>
            $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<CONFIG:Debug>>:-g>
            $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<CONFIG:Debug>>:-g>)
    endif()

    # A target without any .cu file is plain C++; it must not pull in the CUDA
    # runtime.
    if(has_cuda)
        target_link_libraries(${target} PRIVATE CUDA::cudart)
        set_target_properties(${target} PROPERTIES CUDA_RUNTIME_LIBRARY Static)
    endif()

    # OpenCL demos link the ICD loader; it is a normal C++ library, so unlike
    # CUDA it needs no special compile settings beyond the include path the
    # target already carries.
    if(has_opencl)
        target_link_libraries(${target} PRIVATE OpenCL::OpenCL)
    endif()

    # fmt is a general-purpose dependency, so every target links it; an
    # unused link is dropped by --as-needed.
    target_link_libraries(${target} PRIVATE fmt::fmt)
endfunction()

# ---------------------------------------------------------------------------
# Shared code
#
#   src/common/*.cpp,*.cu   ->  static library cudalab_common
#
# Demos link this library, and because src/ is one of its PUBLIC include
# directories they reach the headers as "common/random.h".
# ---------------------------------------------------------------------------
set(CUDALAB_COMMON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/common")

file(GLOB common_sources CONFIGURE_DEPENDS
    "${CUDALAB_COMMON_DIR}/*.cpp"
    "${CUDALAB_COMMON_DIR}/*.cxx"
    "${CUDALAB_COMMON_DIR}/*.cc"
    "${CUDALAB_COMMON_DIR}/*.cu")

if(common_sources)
    set(common_has_cuda FALSE)
    foreach(source IN LISTS common_sources)
        if(source MATCHES "\\.cu$")
            set(common_has_cuda TRUE)
        endif()
    endforeach()

    add_library(cudalab_common STATIC ${common_sources})
    target_include_directories(cudalab_common PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")
    cudalab_configure_target(cudalab_common ${common_has_cuda} FALSE)

    if(common_has_cuda)
        message(STATUS "cudalab: shared library -> cudalab_common (${common_sources}) (CUDA)")
    else()
        message(STATUS "cudalab: shared library -> cudalab_common (${common_sources}) (C++ only)")
    endif()
else()
    message(STATUS "cudalab: no shared sources under ${CUDALAB_COMMON_DIR}")
endif()

# ---------------------------------------------------------------------------
# CTest and Catch2 (Catch2 is installed by vcpkg from vcpkg.json)
#
#   tests/*.cpp                 ->  target cudalab_tests
#   src/demos/<demo>/test*.cpp  ->  target <demo>_test
#
# include(CTest) is what writes DartConfiguration.tcl into the build tree. Plain
# `ctest` does not need it, but `ctest -T test` - the dashboard mode VS Code's
# CMake Tools drives - reads it and fails with "Cannot find file:
# DartConfiguration.tcl" when it is missing. include(CTest) also enables testing
# and defines the conventional BUILD_TESTING switch, so tests run only when both
# it and CUDALAB_BUILD_TESTS are on.
#
# Catch2 has to be located here, before the demo loop: the loop builds a test
# target for every demo that ships a test source, and each of those links it.
# A checkout without a vcpkg root keeps working, the tests simply stay off.
# ---------------------------------------------------------------------------
include(CTest)

option(CUDALAB_BUILD_TESTS "Build the Catch2 unit tests" ON)

set(CUDALAB_CATCH2_AVAILABLE FALSE)

if(CUDALAB_BUILD_TESTS AND BUILD_TESTING)
    find_package(Catch2 3 CONFIG QUIET)
    if(Catch2_FOUND)
        set(CUDALAB_CATCH2_AVAILABLE TRUE)
        include(Catch)
        message(STATUS "cudalab: Catch2 ${Catch2_VERSION} found -> unit tests enabled")
    else()
        message(WARNING
            "cudalab: Catch2 not found - unit tests disabled. No usable vcpkg "
            "installation was found (set VCPKG_ROOT, put vcpkg on PATH, or "
            "install the vcpkg component in Visual Studio), or this build tree "
            "was first configured before vcpkg was added: CMake reads "
            "CMAKE_TOOLCHAIN_FILE only on a build tree's first configure, so "
            "delete ${CMAKE_BINARY_DIR} and configure again.")
    endif()
elseif(NOT BUILD_TESTING)
    message(STATUS "cudalab: BUILD_TESTING=OFF, unit tests disabled")
endif()

# The tests/ directory is independent of the demos. cudalab_common already
# exists at this point, which is the one thing the tests link.
if(CUDALAB_CATCH2_AVAILABLE AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/CMakeLists.txt")
    add_subdirectory(tests)
endif()

# ---------------------------------------------------------------------------
# Demo layout
#
#   src/demos/<demo_name>/       ->  executable target <demo_name>
#
# Every subdirectory of src/demos is one self-contained demo and becomes one
# executable target named after the directory. Sources are all the .cu/.cpp
# files directly inside it (headers are picked up through the include path);
# adding a demo means adding a directory, not editing this file.
# ---------------------------------------------------------------------------
set(CUDALAB_DEMOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/demos")

# Optional subset: -DCUDALAB_DEMOS="demo_add_one;demo_bitonic_sort"
set(CUDALAB_DEMOS "" CACHE STRING
    "Semicolon-separated demos to build; empty builds every demo under src/demos")

# --- Discover demos --------------------------------------------------------
file(GLOB demo_entries CONFIGURE_DEPENDS
    RELATIVE "${CUDALAB_DEMOS_DIR}"
    "${CUDALAB_DEMOS_DIR}/*")

set(demo_names "")
foreach(entry IN LISTS demo_entries)
    if(IS_DIRECTORY "${CUDALAB_DEMOS_DIR}/${entry}")
        list(APPEND demo_names "${entry}")
    endif()
endforeach()
list(SORT demo_names)

if(CUDALAB_DEMOS)
    set(selected_demos "")
    foreach(wanted IN LISTS CUDALAB_DEMOS)
        if(wanted IN_LIST demo_names)
            list(APPEND selected_demos "${wanted}")
        else()
            message(WARNING
                "cudalab: CUDALAB_DEMOS requests '${wanted}', which is not a directory under ${CUDALAB_DEMOS_DIR}")
        endif()
    endforeach()
    set(demo_names "${selected_demos}")
endif()

# --- One executable target per demo ----------------------------------------
set(demo_count 0)
set(cudalab_demo_targets "")
set(cudalab_test_targets "")

foreach(demo IN LISTS demo_names)
    set(demo_dir "${CUDALAB_DEMOS_DIR}/${demo}")

    file(GLOB demo_all_sources CONFIGURE_DEPENDS
        "${demo_dir}/*.cu"
        "${demo_dir}/*.cpp"
        "${demo_dir}/*.cxx"
        "${demo_dir}/*.cc")

    # A .cl file marks the demo as using OpenCL. The kernel is loaded at
    # runtime by the driver rather than compiled into the executable, so it is
    # only used to decide whether to link OpenCL - never added to the target.
    file(GLOB demo_cl_sources CONFIGURE_DEPENDS "${demo_dir}/*.cl")

    if(NOT demo_all_sources)
        # Happens while a demo directory exists but is still empty; skipping
        # keeps a work-in-progress directory from breaking the configure step.
        message(STATUS "cudalab: skipping '${demo}' - no .cu/.cpp sources yet")
        continue()
    endif()

    # Split the directory by role. By convention the driver is main.* and a
    # Catch2 test is test*.cpp / test_*.cpp; everything else is the demo's own
    # implementation. The executable is driver + implementation, the test
    # target implementation + test - each brings its own main, which is why the
    # driver must stay out of the test.
    set(demo_sources "")
    set(demo_impl_sources "")
    set(demo_test_sources "")
    foreach(source IN LISTS demo_all_sources)
        get_filename_component(source_name "${source}" NAME)
        if(source_name MATCHES "^test.*\\.(cu|cpp|cxx|cc)$")
            list(APPEND demo_test_sources "${source}")
        else()
            list(APPEND demo_sources "${source}")
            if(NOT source_name MATCHES "^main\\.(cu|cpp|cxx|cc)$")
                list(APPEND demo_impl_sources "${source}")
            endif()
        endif()
    endforeach()

    add_executable(${demo} ${demo_sources})
    list(APPEND cudalab_demo_targets "${demo}")

    # The demo's own directory holds its headers, so `#include "add_one.h"`
    # resolves without any extra setup.
    target_include_directories(${demo} PRIVATE "${demo_dir}")

    # Shared headers, if the project ever grows any.
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/include")
        target_include_directories(${demo} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
    endif()

    # Shared code, and with it the src/ include directory.
    if(TARGET cudalab_common)
        target_link_libraries(${demo} PRIVATE cudalab_common)
    endif()

    set(demo_has_cuda FALSE)
    foreach(source IN LISTS demo_sources)
        if(source MATCHES "\\.cu$")
            set(demo_has_cuda TRUE)
        endif()
    endforeach()

    set(demo_has_opencl FALSE)
    if(demo_cl_sources)
        set(demo_has_opencl TRUE)
    endif()

    cudalab_configure_target(${demo} ${demo_has_cuda} ${demo_has_opencl})

    if(demo_has_cuda AND demo_has_opencl)
        message(STATUS "cudalab: demo '${demo}' -> target ${demo} (CUDA + OpenCL)")
    elseif(demo_has_cuda)
        message(STATUS "cudalab: demo '${demo}' -> target ${demo} (CUDA)")
    elseif(demo_has_opencl)
        message(STATUS "cudalab: demo '${demo}' -> target ${demo} (OpenCL)")
    else()
        message(STATUS "cudalab: demo '${demo}' -> target ${demo} (C++ only)")
    endif()

    # --- The demo's own Catch2 tests, when it has a test*.cpp ---------------
    if(demo_test_sources)
        if(CUDALAB_CATCH2_AVAILABLE)
            set(demo_test_target "${demo}_test")

            add_executable(${demo_test_target} ${demo_impl_sources} ${demo_test_sources})
            target_include_directories(${demo_test_target} PRIVATE "${demo_dir}")
            if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/include")
                target_include_directories(${demo_test_target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
            endif()
            if(TARGET cudalab_common)
                target_link_libraries(${demo_test_target} PRIVATE cudalab_common)
            endif()
            target_link_libraries(${demo_test_target} PRIVATE Catch2::Catch2WithMain)

            set(demo_test_has_cuda FALSE)
            foreach(source IN LISTS demo_impl_sources demo_test_sources)
                if(source MATCHES "\\.cu$")
                    set(demo_test_has_cuda TRUE)
                endif()
            endforeach()

            # The test target reuses the demo's implementation sources, so it
            # needs the same OpenCL linkage as the driver when the demo ships a
            # .cl kernel.
            set(demo_test_has_opencl ${demo_has_opencl})

            cudalab_configure_target(${demo_test_target} ${demo_test_has_cuda} ${demo_test_has_opencl})

            # The [benchmark] case runs with the rest of the suite, so `ctest`
            # exercises it as well; the sample count is trimmed here so the
            # timing table does not dominate the run. Run the binary directly
            # for Catch2's full default of 100 samples.
            #
            # PRE_TEST discovery (rather than the POST_BUILD default) matters for
            # the IDE flow: with POST_BUILD, CTest keeps a `<target>_NOT_BUILT`
            # placeholder until the test target itself has been built, and VS
            # Code's Test integration builds the *active* target - a demo driver,
            # not the test - then runs ctest, so the placeholder survives and
            # every run reports "Could not find executable". PRE_TEST discovers
            # at ctest startup, which only needs the test binary to exist.
            catch_discover_tests(${demo_test_target}
                EXTRA_ARGS --benchmark-samples 20 --benchmark-resamples 1000
                DISCOVERY_MODE PRE_TEST)

            # Tying the test binary to the build is handled after the loop:
            # ctest runs *every* test binary, so a single aggregate target makes
            # all of them build no matter which target the IDE picked.
            list(APPEND cudalab_test_targets "${demo_test_target}")

            if(demo_test_has_cuda AND demo_test_has_opencl)
                message(STATUS "cudalab: demo '${demo}' tests -> target ${demo_test_target} (CUDA + OpenCL)")
            elseif(demo_test_has_cuda)
                message(STATUS "cudalab: demo '${demo}' tests -> target ${demo_test_target} (CUDA)")
            elseif(demo_test_has_opencl)
                message(STATUS "cudalab: demo '${demo}' tests -> target ${demo_test_target} (OpenCL)")
            else()
                message(STATUS "cudalab: demo '${demo}' tests -> target ${demo_test_target} (C++ only)")
            endif()
        else()
            message(STATUS "cudalab: demo '${demo}' ships tests but testing is off (BUILD_TESTING/CUDALAB_BUILD_TESTS), skipping ${demo}_test")
        endif()
    endif()

    # A .cl kernel is opened by name at runtime from the working directory,
    # which is the build directory, so stage each kernel next to the
    # executables. The copy is tracked as a file dependency, so editing a
    # kernel re-stages it on the next build - it is a build step, not a source
    # of the target.
    if(demo_cl_sources)
        foreach(cl_source IN LISTS demo_cl_sources)
            get_filename_component(cl_name "${cl_source}" NAME)
            set(staged_cl "${CMAKE_CURRENT_BINARY_DIR}/${cl_name}")
            add_custom_command(
                OUTPUT "${staged_cl}"
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${cl_source}" "${staged_cl}"
                DEPENDS "${cl_source}"
                VERBATIM)
            set(stage_target "${demo}_stage_${cl_name}")
            add_custom_target(${stage_target} DEPENDS "${staged_cl}")
            add_dependencies(${demo} ${stage_target})
            if(demo_test_target)
                add_dependencies(${demo_test_target} ${stage_target})
            endif()
        endforeach()
    endif()

    math(EXPR demo_count "${demo_count} + 1")
endforeach()

message(STATUS "cudalab: ${demo_count} demo target(s) configured from ${CUDALAB_DEMOS_DIR}")

# ---------------------------------------------------------------------------
# ctest runs every test binary, so whichever target the IDE builds has to build
# them all. The IDE builds the *active* target - normally one demo driver - not
# `all`, so each demo is made to depend on one aggregate target that pulls in
# every test executable. That way `cmake --build --target demo_add_one` (or any
# other demo) leaves ctest with real tests and no `<target>_NOT_BUILT`
# placeholder; with PRE_TEST discovery that placeholder is the only thing ctest
# can fall back to when a test binary is missing.
# ---------------------------------------------------------------------------
if(cudalab_test_targets)
    add_custom_target(cudalab_build_tests)
    add_dependencies(cudalab_build_tests ${cudalab_test_targets})
    foreach(demo_target IN LISTS cudalab_demo_targets)
        add_dependencies(${demo_target} cudalab_build_tests)
    endforeach()
    message(STATUS "cudalab: demo targets depend on cudalab_build_tests (${cudalab_test_targets})")
endif()
