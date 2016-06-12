/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.config;

public import voxelman.globalconfig;
public import dlib.math.vector : vec3, ivec3, ivec4, uvec2;

alias BlockId = ubyte;
alias TimestampType = uint;
alias DimentionId = ushort;

enum CHUNK_SIZE = 32;
enum CHUNK_SIZE_BITS = CHUNK_SIZE - 1;
enum CHUNK_SIZE_SQR = CHUNK_SIZE * CHUNK_SIZE;
enum CHUNK_SIZE_CUBE = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;
enum CHUNK_SIZE_VECTOR = ivec3(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE);

enum REGION_SIZE = 16;
enum REGION_SIZE_SQR = REGION_SIZE * REGION_SIZE;
enum REGION_SIZE_CUBE = REGION_SIZE * REGION_SIZE * REGION_SIZE;

immutable string DEFAULT_WORLD_NAME = "world";

enum DEFAULT_VIEW_RADIUS = 6;
enum MIN_VIEW_RADIUS = 1;
enum MAX_VIEW_RADIUS = 100;
enum WORLD_SIZE = 12; // chunks
enum BOUND_WORLD = false;

enum START_POS = vec3(80, 10, 0);

enum ENABLE_RLE_PACKET_COMPRESSION = false;

enum SERVER_UPDATES_PER_SECOND = 20;
enum size_t SERVER_FRAME_TIME_USECS = 1_000_000 / SERVER_UPDATES_PER_SECOND;
enum SERVER_PORT = 1234;

enum QUEUE_LENGTH = 1024*1024*1;
enum MAX_LOAD_QUEUE_LENGTH = QUEUE_LENGTH / 2;
