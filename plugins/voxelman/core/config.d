/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.config;

public import voxelman.globalconfig;
import std.experimental.logger;
import dlib.math.vector : vec3, ivec3, ivec4, uvec2;

alias BlockId = ubyte;
alias TimestampType = ulong;

enum CHUNK_SIZE = 32;
enum CHUNK_SIZE_BITS = CHUNK_SIZE - 1;
enum CHUNK_SIZE_SQR = CHUNK_SIZE * CHUNK_SIZE;
enum CHUNK_SIZE_CUBE = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

// directories
enum string WORLD_FILE_NAME = "worldinfo.cbor";
immutable string DEFAULT_WORLD_NAME = "world";

enum NUM_WORKERS = 4;
enum DEFAULT_VIEW_RADIUS = 5;
enum MIN_VIEW_RADIUS = 1;
enum MAX_VIEW_RADIUS = 100;
enum WORLD_SIZE = 12; // chunks
enum BOUND_WORLD = false;

enum START_POS = vec3(80, -40, 0);

enum ENABLE_RLE_PACKET_COMPRESSION = false;

enum SERVER_UPDATES_PER_SECOND = 20;
enum size_t SERVER_FRAME_TIME_USECS = 1_000_000 / SERVER_UPDATES_PER_SECOND;
enum SERVER_PORT = 1234;

enum MAX_LOAD_QUEUE_LENGTH = 1000;
