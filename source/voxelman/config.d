/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.config;

import dlib.math.vector : vec3, ivec3, ivec4;

alias BlockType = ubyte;
alias TimestampType = uint;

enum CHUNK_SIZE = 32;
enum CHUNK_SIZE_BITS = CHUNK_SIZE - 1;
enum CHUNK_SIZE_SQR = CHUNK_SIZE * CHUNK_SIZE;
enum CHUNK_SIZE_CUBE = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

// directories
enum string SAVE_DIR = "../saves";
enum string WORLD_NAME = "world";
enum string WORLD_DIR = SAVE_DIR ~ "/" ~ WORLD_NAME;
enum string WORLD_FILE_NAME = "worldinfo.cbor";


enum NUM_WORKERS = 4;
enum VIEW_RADIUS = 2;
enum WORLD_SIZE = 12; // chunks
enum BOUND_WORLD = false;

enum START_POS = vec3(0, 100, 0);
enum CAMERA_SENSIVITY = 0.4;

enum CONNECT_ADDRESS = "127.0.0.1";
enum CONNECT_PORT = 1234;

enum ENABLE_RLE_PACKET_COMPRESSION = true;

enum SERVER_UPDATES_PER_SECOND = 120;
enum size_t SERVER_FRAME_TIME_USECS = 1_000_000 / SERVER_UPDATES_PER_SECOND;
