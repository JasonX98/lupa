cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# 开发便利：构建后把发布期数据文件复制到输出旁，
# 让 `flutter run -d windows` / `flutter build windows --release` 产出开箱即用的目录：
#   dict.sqlite  → lupa_data/（便携默认词库，不入仓，缺失时静默跳过）
#   schema.sql   → data/（首次建库模板，app 必需）
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND}
    "-DLUPA_DICT_SRC=${CMAKE_CURRENT_SOURCE_DIR}/../../../data/dict.sqlite"
    "-DLUPA_DICT_DST=$<TARGET_FILE_DIR:${BINARY_NAME}>/lupa_data/dict.sqlite"
    "-DLUPA_SCHEMA_SRC=${CMAKE_CURRENT_SOURCE_DIR}/../../lib/data/schema.sql"
    "-DLUPA_SCHEMA_DST=$<TARGET_FILE_DIR:${BINARY_NAME}>/data/schema.sql"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/copy_data_files.cmake"
  VERBATIM
)
