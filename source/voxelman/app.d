/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.app;

import std.stdio : writeln;
import std.string : format;
import std.parallelism;

import dlib.math.matrix;
import dlib.math.affine;

import anchovy.graphics.windows.glfwwindow;
import anchovy.gui;
import anchovy.gui.application.application;
import anchovy.gui.databinding.list;

import voxelman.fpscontroller;
import voxelman.camera;

class VoxelApplication : Application!GlfwWindow
{
	__gshared ChunkMan chunkMan;
	uvec3 viewSize;
	ulong chunksRendered;
	ulong vertsRendered;
	ulong trisRendered;

	ShaderProgram chunkShader;
	GLuint cameraToClipMatrixLoc, worldToCameraMatrixLoc, modelToWorldMatrixLoc;

	FpsController fpsController;
	bool mouseLocked;

	Widget debugInfo;

	this(uvec2 windowSize, string caption)
	{
		super(windowSize, caption);
	}

	void addHideHandler(string frameId)
	{
		auto frame = context.getWidgetById(frameId);
		Widget closeButton = frame["subwidgets"].get!(Widget[string])["close"];
		closeButton.addEventHandler(delegate bool(Widget widget, PointerClickEvent event){
			frame["isVisible"] = false;
			return true;
		});
	}

	void setupFrameShowButton(string buttonId, string frameId)
	{
		auto frame = context.getWidgetById(frameId);
		context.getWidgetById(buttonId).addEventHandler(delegate bool(Widget widget, PointerClickEvent event){
			frame["isVisible"] = true;
			return true;
		});
	}

	override void load(in string[] args)
	{
		writeln("---------------------- System info ----------------------");
		foreach(item; getHardwareInfo())
			writeln(item);
		writeln("---------------------------------------------------------\n");

		fpsHelper.limitFps = false;

		// Setup rendering

		clearColor = Color(255, 255, 255);
		renderer.setClearColor(clearColor);

		fpsController = new FpsController;
		fpsController.move(vec3(0, 4, 64));
		fpsController.camera.sensivity = 0.4;

		// Setupr shaders

		string vShader = cast(string)read("perspective.vert");		
		string fShader = cast(string)read("colored.frag");		
		chunkShader = new ShaderProgram(vShader, fShader);

		if(!chunkShader.compile())
		{
			writeln(chunkShader.errorLog);
		}
		else
		{
			writeln("Shaders compiled successfully");
		}

		chunkShader.bind;
			modelToWorldMatrixLoc = glGetUniformLocation( chunkShader.program, "modelToWorldMatrix" );//model transformation
			worldToCameraMatrixLoc = glGetUniformLocation( chunkShader.program, "worldToCameraMatrix" );//camera trandformation
			cameraToClipMatrixLoc = glGetUniformLocation( chunkShader.program, "cameraToClipMatrix" );//perspective	

			glUniformMatrix4fv(modelToWorldMatrixLoc, 1, GL_FALSE, cast(const float*)Matrix4f.identity.arrayof);
			glUniformMatrix4fv(worldToCameraMatrixLoc, 1, GL_FALSE, cast(const float*)fpsController.cameraMatrix);
			glUniformMatrix4fv(cameraToClipMatrixLoc, 1, GL_FALSE, cast(const float*)fpsController.camera.perspective.arrayof);
		chunkShader.unbind;

		// Bind events

		aggregator.window.windowResized.connect(&windowResized);
		aggregator.window.keyReleased.connect(&keyReleased);

		// ----------------------------- Creating widgets -----------------------------
		templateManager.parseFile("voxelman.sdl");

		auto mainLayer = context.createWidget("mainLayer");
		context.addRoot(mainLayer);

		auto frameLayer = context.createWidget("frameLayer");
		context.addRoot(frameLayer);

		// Frames
		addHideHandler("infoFrame");
		addHideHandler("settingsFrame");

		setupFrameShowButton("showInfo", "infoFrame");
		setupFrameShowButton("showSettings", "settingsFrame");

		debugInfo = context.getWidgetById("debugInfo");
		foreach(i; 0..10) context.createWidget("label", debugInfo);

		writeln("\n----------------------------- Load end -----------------------------\n");

		// ----------------------------- init chunks ---------------------------

		chunkMan.init();
		chunkMan.loadRegion(ChunkRegion(ChunkCoord(-10, -5, -10), uvec3(50, 10, 50)));
	}

	ulong lastFrameLoadedChunks = 0;
	override void update(double dt)
	{
		fpsHelper.update(dt);

		printDebug();

		timerManager.updateTimers(window.elapsedTime);
		context.update(dt);

		updateController(dt);
	}

	void printDebug()
	{
		// Print debug info
		auto lines = debugInfo.getPropertyAs!("children", Widget[]);

		lines[ 0]["text"] = format("FPS: %s", fpsHelper.fps).to!dstring;
		lines[ 1]["text"] = format("Chunks %s", chunksRendered).to!dstring;
		chunksRendered = 0;

		ulong chunksLoaded = totalLoadedChunks;
		lines[ 2]["text"] = format("Chunks per frame loaded: %s",
			chunksLoaded - lastFrameLoadedChunks).to!dstring;
		lines[ 3]["text"] = format("Chunks total loaded: %s",
			chunksLoaded).to!dstring;
		lastFrameLoadedChunks = chunksLoaded;

		lines[ 4]["text"] = format("Vertexes %s", vertsRendered).to!dstring;
		vertsRendered = 0;
		lines[ 5]["text"] = format("Triangles %s", trisRendered).to!dstring;
		trisRendered = 0;

		vec3 pos = fpsController.camera.position;
		lines[ 6]["text"] = format("Position: X %.2f, Y %.2f, Z %.2f",
			pos.x, pos.y, pos.z).to!dstring;

		vec3 target = fpsController.camera.target;
		lines[ 7]["text"] = format("Target: X %.2f, Y %.2f, Z %.2f",
			target.x, target.y, target.z).to!dstring;
	}

	void windowResized(uvec2 newSize)
	{
		fpsController.camera.aspect = cast(float)newSize.x/newSize.y;
		fpsController.camera.updatePerspective();
	}

	override void draw()
	{
		guiRenderer.setClientArea(Rect(0, 0, window.size.x, window.size.y));
		glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);

		renderer.disableAlphaBlending();
		drawScene();
		renderer.enableAlphaBlending();

		context.eventDispatcher.draw();

		window.swapBuffers();
	}

	void drawScene()
	{
		glEnable(GL_DEPTH_TEST);
		
		chunkShader.bind;
		glUniformMatrix4fv(worldToCameraMatrixLoc, 1, GL_FALSE,
			fpsController.cameraMatrix);
		glUniformMatrix4fv(cameraToClipMatrixLoc, 1, GL_FALSE,
			cast(const float*)fpsController.camera.perspective.arrayof);

		Matrix4f modelToWorldMatrix;
		foreach(Chunk* c; chunkMan.visibleChunks)
		{
			// Frustum culling
			/*svec4 svecMin = c.coord.vector * chunkSize;
			vec3 vecMin = vec3(svecMin.x, svecMin.y, svecMin.z);
			vec3 vecMax = vecMin + chunkSize;
			auto result = fpsController.camera.frustumAABBIntersect(vecMin, vecMax);
			if (result == IntersectionResult.outside) continue;*/

			modelToWorldMatrix = translationMatrix!float(c.mesh.position);
			glUniformMatrix4fv(modelToWorldMatrixLoc, 1, GL_FALSE,
				cast(const float*)modelToWorldMatrix.arrayof);
			
			c.mesh.bind;
			c.mesh.render;
			++chunksRendered;
			vertsRendered += c.mesh.numVertexes;
			trisRendered += c.mesh.numTris;
		}
		chunkShader.unbind;

		glDisable(GL_DEPTH_TEST);
		
		renderer.setColor(Color(0,0,0,1));
		//renderer.drawRect(Rect(width/2-7, height/2-1, 14, 2));
		//renderer.drawRect(Rect(width/2-1, height/2-7, 2, 14));
	}

	void updateController(double dt)
	{
		if(mouseLocked)
		{
			ivec2 mousePos = window.mousePosition;
			mousePos -= cast(ivec2)(window.size) / 2;

			if(mousePos.x !=0 || mousePos.y !=0)
			{
				fpsController.rotateHor(mousePos.x);
				fpsController.rotateVert(mousePos.y);
			}
			window.mousePosition = cast(ivec2)(window.size) / 2;

			uint cameraSpeed = 30;
			vec3 posDelta = vec3(0,0,0);
			if(window.isKeyPressed(KeyCode.KEY_LEFT_SHIFT)) cameraSpeed = 80;

			if(window.isKeyPressed(KeyCode.KEY_D)) posDelta.x = 1;
			else if(window.isKeyPressed(KeyCode.KEY_A)) posDelta.x = -1;

			if(window.isKeyPressed(KeyCode.KEY_W)) posDelta.z = 1;
			else if(window.isKeyPressed(KeyCode.KEY_S)) posDelta.z = -1;

			if(window.isKeyPressed(GLFW_KEY_SPACE)) posDelta.y = 1;
			else if(window.isKeyPressed(GLFW_KEY_LEFT_CONTROL)) posDelta.y = -1;

			if (posDelta != vec3(0))
			{
				posDelta *= cameraSpeed * dt;
				fpsController.moveAxis(posDelta);
			}
		}
	}

	void keyReleased(uint keyCode)
	{
		switch(keyCode)
		{
			case KeyCode.KEY_Q: mouseLocked = !mouseLocked;
				if (mouseLocked)
					window.mousePosition = cast(ivec2)(window.size) / 2;
				break;
			case KeyCode.KEY_P: fpsController.printVectors; break;
			case KeyCode.KEY_I: fpsController.moveAxis(vec3(0, 0, 1)); break;
			case KeyCode.KEY_K: fpsController.moveAxis(vec3(0, 0, -1)); break;
			case KeyCode.KEY_J: fpsController.moveAxis(vec3(-1, 0, 0)); break;
			case KeyCode.KEY_L: fpsController.moveAxis(vec3(1, 0, 0)); break;
			case KeyCode.KEY_O: fpsController.moveAxis(vec3(0, 1, 0)); break;
			case KeyCode.KEY_U: fpsController.moveAxis(vec3(0, -1, 0)); break;
			case KeyCode.KEY_UP: fpsController.rotateVert(-45); break;
			case KeyCode.KEY_DOWN: fpsController.rotateVert(45); break;
			case KeyCode.KEY_LEFT: fpsController.rotateHor(-45); break;
			case KeyCode.KEY_RIGHT: fpsController.rotateHor(45); break;
			case KeyCode.KEY_R: resetCamera(); break;
			default: break;
		}
	}

	void resetCamera()
	{
		fpsController.camera.position=vec3(0,0,0);
		fpsController.angleHor = 0;
		fpsController.angleVert = 0;		
		fpsController.update();
	}

	override void closePressed()
	{
		isRunning = false;
	}
}

//------------------------------------------------------------------------------
//------------------------------- Chunk storage --------------------------------
//------------------------------------------------------------------------------

import std.algorithm : filter;
import std.conv : to;
import voxelman.chunkmesh;

enum chunkSize = 16;
alias BlockType = ubyte;
alias Vector!(short, 4) svec4;

// chunk position in chunk coordinate space
struct ChunkCoord
{
	union
	{
		struct
		{
			short x, y, z;
			short _;
		}
		svec4 vector;
		ulong asLong;
	}

	alias vector this;

	string toString()
	{
		return format("{%s %s %s}", x, y, z);
	}
}

// 3d slice of chunks
struct ChunkRegion
{
	ChunkCoord coord;
	uvec3 size;

	bool contains(ChunkCoord otherCoord)
	{
		if (otherCoord.x < coord.x || otherCoord.x >= coord.x + size.x) return false;
		if (otherCoord.y < coord.y || otherCoord.y >= coord.y + size.y) return false;
		if (otherCoord.z < coord.z || otherCoord.z >= coord.z + size.z) return false;
		return true;
	}

	auto chunksNotIn(ChunkRegion other)
	{

	}
}

// Chunk data
struct ChunkData
{
	/// null if homogeneous is true, or contains chunk data otherwise
	BlockType[] typeData;
	/// type of common block
	BlockType uniformType = 0; // Unknown block
	/// is chunk filled with block of the same type
	bool uniform = true;
}

// Single chunk
struct Chunk
{
	@disable this();

	this(ChunkCoord coord)
	{
		this.coord = coord;
		mesh = new ChunkMesh();
	}

	BlockType getBlockType(ubyte cx, ubyte cy, ubyte cz)
	{
		if (data.uniform) return data.uniformType;
		return data.typeData[cx + cy*chunkSize^^2 + cz*chunkSize];
	}

	ChunkData data;
	ChunkMesh mesh;
	ChunkCoord coord;
	Chunk*[6] neighbours;

	bool isLoaded = false;
	bool isVisible = false;
	bool hasMesh = false;
}

// Chunk storage
struct ChunkMan
{
	__gshared ChunkRegion visibleRegion;
	__gshared Chunk*[ulong] chunks;
	ChunkCoord observerPosition;
	uint observeRadius;
	IBlock[] blockTypes;

	Chunk* unknownChunk;

	void init()
	{
		loadBlockTypes();
		unknownChunk = new Chunk(ChunkCoord(0, 0, 0));
	}

	void loadBlockTypes()
	{
		blockTypes ~= new UnknownBlock(0);
		blockTypes ~= new AirBlock(1);
		blockTypes ~= new SolidBlock(2);
	}

	Chunk* createEmptyChunk(ChunkCoord coord)
	{
		return new Chunk(coord);
	}

	Chunk* getChunk(ChunkCoord coord)
	{
		Chunk** chunk = coord.asLong in chunks;
		if (chunk is null) return unknownChunk;
		return *chunk;
	}

	@property auto visibleChunks()
	{
		return chunks
		.byValue
		.filter!((c) => c.isLoaded && c.isVisible);
	}

	void updateObserverPosition(vec3 cameraPos)
	{
		ChunkCoord chunkPos = ChunkCoord(
			to!short(cameraPos.x) >> 4,
			to!short(cameraPos.y) >> 4,
			to!short(cameraPos.z) >> 4);

		if (chunkPos == observerPosition) return;

		ChunkRegion newRegion = ChunkRegion(
			cast(ChunkCoord)(chunkPos.vector - cast(short)observeRadius),
			visibleRegion.size);
		updateVisibleRegion(newRegion);
	}

	void updateVisibleRegion(ChunkRegion newRegion)
	{
		auto oldRegion = visibleRegion;
		visibleRegion = newRegion;

		if (oldRegion.size == uvec3(0, 0, 0))
		{
			loadRegion(visibleRegion);
			return;
		}


	}

	// Add already created chunk to storage
	// Sets up all neighbours
	void addChunk(Chunk* chunk)
	{
		chunks[chunk.coord.asLong] = chunk;
		ChunkCoord coord = chunk.coord;

		void attachNeighbour(ubyte side)()
		{
			byte[3] offset = sideOffsets[side];
			ChunkCoord otherCoord = ChunkCoord(cast(short)(coord.x + offset[0]),
												cast(short)(coord.y + offset[1]),
												cast(short)(coord.z + offset[2]));
			Chunk* other = getChunk(otherCoord);

			other.neighbours[oppSide[side]] = chunk;
			chunk.neighbours[side] = other;
		}

		// Attach all neighbours
		attachNeighbour!(0)();
		attachNeighbour!(1)();
		attachNeighbour!(2)();
		attachNeighbour!(3)();
		attachNeighbour!(4)();
		attachNeighbour!(5)();
	}

	void removeChunk(Chunk* chunk)
	{
		if (chunk is unknownChunk) return;

		void detachNeighbour(ubyte side)()
		{
			if (chunk.neighbours[side])
			{
				chunk.neighbours[side].neighbours[oppSide[side]] = unknownChunk;
				chunk.neighbours[side] = null;
			}
		}

		// Detach all neighbours
		detachNeighbour!(0)();
		detachNeighbour!(1)();
		detachNeighbour!(2)();
		detachNeighbour!(3)();
		detachNeighbour!(4)();
		detachNeighbour!(5)();

		chunks.remove(chunk.coord.asLong);
	}

	void loadChunk(ChunkCoord coord)
	{
		Chunk* chunk = createEmptyChunk(coord);
		addChunk(chunk);
		
		auto pool = taskPool();
		pool.put(task!chunkGenWorker(chunk, &this));
		++numLoadChunkTasks;
	}

	void loadRegion(ChunkRegion region)
	{
		foreach(short x; region.coord.x..cast(short)(region.coord.x + region.size.x))
		foreach(short y; region.coord.y..cast(short)(region.coord.y + region.size.y))
		foreach(short z; region.coord.z..cast(short)(region.coord.z + region.size.z))
		{
			loadChunk(ChunkCoord(x, y, z));
		}
	}
}

// Stats
__gshared ulong numLoadChunkTasks;
__gshared ulong totalLoadedChunks;

//------------------------------------------------------------------------------
//----------------------- Chunk generation -------------------------------------
//------------------------------------------------------------------------------

// Gen single chunk
void chunkGenWorker(Chunk* chunk, ChunkMan* cman)
{
	ChunkCoord coord = chunk.coord;

	int wx = coord.x, wy = coord.y, wz = coord.z;

	ChunkData cd;
	cd.typeData = new BlockType[chunkSize^^3];
	cd.uniform = true;
	
	cd.typeData[0] = getBlock3d(
		wx*chunkSize,
		wy*chunkSize,
		wz*chunkSize);
	BlockType type = cd.typeData[0];
	
	int bx, by, bz;
	foreach(i; 1..chunkSize^^3)
	{
		bx = i & (chunkSize-1);
		by = (i>>8) & (chunkSize-1);
		bz = (i>>4) & (chunkSize-1);

		cd.typeData[i] = getBlock3d(
			bx + wx * chunkSize,
			by + wy * chunkSize,
			bz + wz * chunkSize);

		if(cd.uniform && cd.typeData[i] != type)
		{
			cd.uniform = false;
		}
	}

	chunk.isVisible = true;

	if(cd.uniform)
	{
		delete cd.typeData;
		cd.uniformType = type;
		chunk.isVisible = cman.blockTypes[cd.uniformType].isVisible;
	}
	
	chunk.data = cd;
	chunk.isLoaded = true;

	//writefln("Chunk generated at %s uniform %s", chunk.coord, chunk.data.uniform);

	++totalLoadedChunks;

	if (chunk.isVisible)
	{
		auto pool = taskPool();
		pool.put(task!chunkMeshWorker(chunk, cman));
		//chunkMeshWorker(chunk, cman);
	}

}

import anchovy.utils.noise.simplex;

// Gen single block
BlockType getBlock2d( int x, int y, int z)
{
	enum numOctaves = 6;
	enum divider = 50; // bigger - smoother
	enum heightModifier = 4; // bigger - higher

	float noise = 0.0;
	foreach(i; 1..numOctaves+1)
	{
		// [-1; 1]
		noise += Simplex.noise(cast(float)x/(divider*i), cast(float)z/(divider*i))*i*heightModifier;
	}

	if (noise >= y) return 2;
	else return 1;
}

BlockType getBlock3d( int x, int y, int z)
{
	// [-1; 1]
	float noise = Simplex.noise(cast(float)x/42, cast(float)y/42, cast(float)z/42);
	if (noise > 0.5) return 2;
	else return 1;
}

//------------------------------------------------------------------------------
//-------------------------- Block data ----------------------------------------
//------------------------------------------------------------------------------

// mesh for single block
const float[18][6] faces =
[
	[-0.5f,-0.5f,-0.5f, // triangle 1 : begin // north
	 0.5f,-0.5f,-0.5f,
	 0.5f, 0.5f,-0.5f, // triangle 1 : end
	-0.5f,-0.5f,-0.5f, // triangle 2 : begin
	 0.5f, 0.5f,-0.5f,
	-0.5f, 0.5f,-0.5f], // triangle 2 : end

	[0.5f,-0.5f, 0.5f, // south
	-0.5f,-0.5f, 0.5f,
	-0.5f, 0.5f, 0.5f,
	 0.5f,-0.5f, 0.5f,
	-0.5f, 0.5f, 0.5f,
	 0.5f, 0.5f, 0.5f],

	[0.5f,-0.5f,-0.5f, // east
	 0.5f,-0.5f, 0.5f,
	 0.5f, 0.5f, 0.5f,
	 0.5f,-0.5f,-0.5f,
	 0.5f, 0.5f, 0.5f,
	 0.5f, 0.5f,-0.5f],

	[-0.5f,-0.5f, 0.5f, // west
	-0.5f,-0.5f,-0.5f,
	-0.5f, 0.5f,-0.5f,
	-0.5f,-0.5f, 0.5f,
	-0.5f, 0.5f,-0.5f,
	-0.5f, 0.5f, 0.5f],

	[-0.5f,-0.5f, 0.5f, // bottom
	 0.5f,-0.5f, 0.5f,
	 0.5f,-0.5f,-0.5f,
	-0.5f,-0.5f, 0.5f,
	 0.5f,-0.5f,-0.5f,
	-0.5f,-0.5f,-0.5f],

	[0.5f, 0.5f, 0.5f, // top
	-0.5f, 0.5f, 0.5f,
	-0.5f, 0.5f,-0.5f,
	 0.5f, 0.5f, 0.5f,
	-0.5f, 0.5f,-0.5f,
	 0.5f, 0.5f,-0.5f]
];

const float[18] colors =
[0.0,0.7,0.0,
 0.0,0.75,0.0,
 0.0,0.6,0.0,
 0.0,0.5,0.0,
 0.0,0.4,0.0,
 0.0,0.85,0.0,];

enum Side : ubyte
{
	north	= 0,
	south	= 1,
	
	east	= 2,
	west	= 3,
	
	bottom	= 4,
	top		= 5,
}

ubyte[6] oppSide =
[1, 0, 3, 2, 5, 4];

byte[3][6] sideOffsets =
[
	[ 0, 0,-1],
	[ 0, 0, 1],
	[ 1, 0, 0],
	[-1, 0, 0],
	[ 0,-1, 0],
	[ 0, 1, 0],
];

abstract class IBlock
{
	this(BlockType id)
	{
		this.id = id;
	}
	// TODO remake as table
	//Must return true if the side allows light to pass
	bool isSideTransparent(ubyte side);

	bool isVisible();
	
	//Must return mesh for block in given position for given sides
	//sides is contains [6] bit flags of wich side must be builded
	float[] getMesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum);
	
	float texX1, texY1, texX2, texY2;
	BlockType id;
}

class SolidBlock : IBlock
{
	this(BlockType id){super(id);}

	override bool isSideTransparent(ubyte side) {return false;}

	override bool isVisible() {return true;}

	override float[] getMesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum)
	{
		float[] data;
		data.reserve(sidesnum*36);

		foreach(ubyte i; 0..6)
		{
			if (sides & (2^^i))
			{
				for (size_t v = 0; v!=18; v+=3)
				{
					data ~= faces[i][v]  +bx;
					data ~= faces[i][v+1]+by;
					data ~= faces[i][v+2]+bz;
					data ~= colors[i*3..i*3+3];
				} // for v
			} // if
		} // for i

		return data;
	}
}

class UnknownBlock : IBlock
{
	this(BlockType id){super(id);}

	override bool isSideTransparent(ubyte side) {return false;}

	override bool isVisible() {return false;}

	override float[] getMesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum)
	{
		return null;
	}
}

class AirBlock : IBlock
{
	this(BlockType id){super(id);}

	override bool isSideTransparent(ubyte side) {return true;}

	override bool isVisible() {return false;}

	override float[] getMesh(ubyte bx, ubyte by, ubyte bz, ubyte sides, ubyte sidesnum)
	{
		return null;
	}
}

//------------------------------------------------------------------------------
//-------------------- Chunk mesh generation -----------------------------------
//------------------------------------------------------------------------------

void chunkMeshWorker(Chunk* chunk, ChunkMan* cman)
{
	assert(chunk);
	assert(cman);

	Appender!(float[]) appender;
	ubyte bx, by, bz;

	Chunk*[6] cNeigh = chunk.neighbours;

	bool isVisibleBlock(uint id)
	{
		return cman.blockTypes[id].isVisible;
	}
	
	bool getTransparency(int tx, int ty, int tz, ubyte side)
	{
		ubyte x = cast(ubyte)tx;
		ubyte y = cast(ubyte)ty;
		ubyte z = cast(ubyte)tz;

		if(tx == -1) // west
			return cman.blockTypes[ cNeigh[Side.west].getBlockType(chunkSize-1, y, z) ].isSideTransparent(side);
		else if(tx == 16) // east
			return cman.blockTypes[ cNeigh[Side.east].getBlockType(0, y, z) ].isSideTransparent(side);

		if(ty == -1) // bottom
			return cman.blockTypes[ cNeigh[Side.bottom].getBlockType(x, chunkSize-1, z) ].isSideTransparent(side);
		else if(ty == 16) // top
			return cman.blockTypes[ cNeigh[Side.top].getBlockType(x, 0, z) ].isSideTransparent(side);

		if(tz == -1) // north
			return cman.blockTypes[ cNeigh[Side.north].getBlockType(x, y, chunkSize-1) ].isSideTransparent(side);
		else if(tz == 16) // south
			return cman.blockTypes[ cNeigh[Side.south].getBlockType(x, y, 0) ].isSideTransparent(side);
		
		return cman.blockTypes[ chunk.getBlockType(x, y, z) ].isSideTransparent(side);
	}
	
	ubyte sides = 0;
	ubyte sidenum = 0;
	byte[3] offset;

	if (chunk.data.uniform)
	{
		foreach (uint index; 0..chunkSize^^3)
		{
			bx = index & 15, by = (index>>8) & 15, bz = (index>>4) & 15;
			sides = 0;
			sidenum = 0;
			
			foreach(ubyte side; 0..6)
			{
				offset = sideOffsets[side];
				
				if(getTransparency(bx+offset[0], by+offset[1], bz+offset[2], side))
				{	
					sides |= 2^^(side);
					++sidenum;
				}
			}
			
			appender ~= cman.blockTypes[chunk.data.uniformType]
							.getMesh(bx, by, bz, sides, sidenum);
		} // foreach
	}
	else
	foreach (uint index, ref ubyte val; chunk.data.typeData)
	{
		if (isVisibleBlock(val))
		{	
			bx = index & 15, by = (index>>8) & 15, bz = (index>>4) & 15;
			sides = 0;
			sidenum = 0;
			
			foreach(ubyte side; 0..6)
			{
				offset = sideOffsets[side];
				
				if(getTransparency(bx+offset[0], by+offset[1], bz+offset[2], side))
				{	
					sides |= 2^^(side);
					++sidenum;
				}
			}
			
			appender ~= cman.blockTypes[val].getMesh(bx, by, bz, sides, sidenum);
		} // if(val != 0)
	} // foreach

	chunk.mesh.data = cast(ubyte[])appender.data;

	ChunkCoord coord = chunk.coord;
	chunk.mesh.position = vec3(coord.x, coord.y, coord.z) * chunkSize;
	chunk.mesh.isDataDirty = true;
	chunk.hasMesh = chunk.mesh.data.length > 0;

	//writefln("Chunk mesh generated at %s", chunk.coord);
}