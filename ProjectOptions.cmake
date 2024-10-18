include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(test_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(test_setup_options)
  option(test_ENABLE_HARDENING "Enable hardening" ON)
  option(test_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    test_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    test_ENABLE_HARDENING
    OFF)

  test_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR test_PACKAGING_MAINTAINER_MODE)
    option(test_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(test_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(test_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(test_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(test_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(test_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(test_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(test_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(test_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(test_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(test_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(test_ENABLE_PCH "Enable precompiled headers" OFF)
    option(test_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(test_ENABLE_IPO "Enable IPO/LTO" ON)
    option(test_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(test_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(test_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(test_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(test_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(test_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(test_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(test_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(test_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(test_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(test_ENABLE_PCH "Enable precompiled headers" OFF)
    option(test_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      test_ENABLE_IPO
      test_WARNINGS_AS_ERRORS
      test_ENABLE_USER_LINKER
      test_ENABLE_SANITIZER_ADDRESS
      test_ENABLE_SANITIZER_LEAK
      test_ENABLE_SANITIZER_UNDEFINED
      test_ENABLE_SANITIZER_THREAD
      test_ENABLE_SANITIZER_MEMORY
      test_ENABLE_UNITY_BUILD
      test_ENABLE_CLANG_TIDY
      test_ENABLE_CPPCHECK
      test_ENABLE_COVERAGE
      test_ENABLE_PCH
      test_ENABLE_CACHE)
  endif()

  test_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (test_ENABLE_SANITIZER_ADDRESS OR test_ENABLE_SANITIZER_THREAD OR test_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(test_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(test_global_options)
  if(test_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    test_enable_ipo()
  endif()

  test_supports_sanitizers()

  if(test_ENABLE_HARDENING AND test_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR test_ENABLE_SANITIZER_UNDEFINED
       OR test_ENABLE_SANITIZER_ADDRESS
       OR test_ENABLE_SANITIZER_THREAD
       OR test_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${test_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${test_ENABLE_SANITIZER_UNDEFINED}")
    test_enable_hardening(test_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(test_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(test_warnings INTERFACE)
  add_library(test_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  test_set_project_warnings(
    test_warnings
    ${test_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(test_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    test_configure_linker(test_options)
  endif()

  include(cmake/Sanitizers.cmake)
  test_enable_sanitizers(
    test_options
    ${test_ENABLE_SANITIZER_ADDRESS}
    ${test_ENABLE_SANITIZER_LEAK}
    ${test_ENABLE_SANITIZER_UNDEFINED}
    ${test_ENABLE_SANITIZER_THREAD}
    ${test_ENABLE_SANITIZER_MEMORY})

  set_target_properties(test_options PROPERTIES UNITY_BUILD ${test_ENABLE_UNITY_BUILD})

  if(test_ENABLE_PCH)
    target_precompile_headers(
      test_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(test_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    test_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(test_ENABLE_CLANG_TIDY)
    test_enable_clang_tidy(test_options ${test_WARNINGS_AS_ERRORS})
  endif()

  if(test_ENABLE_CPPCHECK)
    test_enable_cppcheck(${test_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(test_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    test_enable_coverage(test_options)
  endif()

  if(test_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(test_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(test_ENABLE_HARDENING AND NOT test_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR test_ENABLE_SANITIZER_UNDEFINED
       OR test_ENABLE_SANITIZER_ADDRESS
       OR test_ENABLE_SANITIZER_THREAD
       OR test_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    test_enable_hardening(test_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
