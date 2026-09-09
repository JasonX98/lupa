# 由 runner/CMakeLists.txt 的 POST_BUILD 调用（-P 脚本模式）：
#   cmake "-DLUPA_DICT_SRC=..." "-DLUPA_DICT_DST=..." \
#         "-DLUPA_SCHEMA_SRC=..." "-DLUPA_SCHEMA_DST=..." -P copy_data_files.cmake
#
# 把发布期数据文件复制到构建输出旁：
#   · dict.sqlite  → lupa_data/dict.sqlite   （便携默认词库；不入仓，缺失时跳过）
#   · schema.sql   → data/schema.sql          （首次建库模板；app 必需）
# 目的：`flutter run -d windows` / `flutter build windows --release` 产出开箱即用的目录。

function(lupa_copy label src dst)
  if(NOT EXISTS "${src}")
    message(STATUS "Lupa: ${label} 源不存在（${src}），跳过")
    return()
  endif()
  get_filename_component(_dir "${dst}" DIRECTORY)
  file(MAKE_DIRECTORY "${_dir}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${src}" "${dst}"
    RESULT_VARIABLE _rc)
  if(_rc EQUAL 0)
    message(STATUS "Lupa: 已复制 ${label} -> ${dst}")
  else()
    message(WARNING "Lupa: ${label} 复制失败 (rc=${_rc})")
  endif()
endfunction()

lupa_copy("dict.sqlite" "${LUPA_DICT_SRC}" "${LUPA_DICT_DST}")
lupa_copy("schema.sql" "${LUPA_SCHEMA_SRC}" "${LUPA_SCHEMA_DST}")
