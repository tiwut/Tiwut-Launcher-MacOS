cmake_minimum_required(VERSION 3.15)
project(TiwutLauncher LANGUAGES NONE)

if(NOT APPLE)
    message(FATAL_ERROR "Tiwut Launcher is optimized exclusively for macOS!")
endif()

add_custom_target(TiwutLauncher ALL
    COMMAND swiftc ${CMAKE_CURRENT_SOURCE_DIR}/src/main.swift -o ${CMAKE_CURRENT_BINARY_DIR}/TiwutLauncher -framework WebKit -framework Cocoa
    SOURCES src/main.swift
)

install(PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/TiwutLauncher DESTINATION bin)
install(FILES src/index.html DESTINATION bin)
