/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.config;

import dlib.math.vector : vec3;

alias BlockType = ubyte;

enum CHUNK_SIZE = 32;
enum CHUNK_SIZE_BITS = CHUNK_SIZE - 1;
enum CHUNK_SIZE_SQR = CHUNK_SIZE * CHUNK_SIZE;
enum CHUNK_SIZE_CUBE = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

enum string SAVE_DIR = "save";
enum NUM_WORKERS = 4;
enum VIEW_RADIUS = 8;
enum WORLD_SIZE = 12; // chunks
enum BOUND_WORLD = false;

enum startPos = vec3(0, 100, 0);