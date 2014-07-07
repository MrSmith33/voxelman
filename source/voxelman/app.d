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

import voxelman.fpscontroller;

class VoxelApplication : Application!GlfwWindow
{
	ChunkMan chunkMan;
	uvec3 viewSize;
	ulong chunksRendered;

	ShaderProgram chunkShader;
	GLuint cameraToClipMatrixLoc, worldToCameraMatrixLoc, modelToWorldMatrixLoc;

	FpsController fpsController;

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

		clearColor = Color(255, 255, 255);
		renderer.setClearColor(clearColor);

		fpsController = new FpsController;

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
		chunkShader.unbind;

		// ----------------------------- Creating widgets -----------------------------
		templateManager.parseFile("voxelman.sdl");

		auto mainLayer = context.createWidget("mainLayer");
		context.addRoot(mainLayer);

		auto frameLayer = context.createWidget("frameLayer");
		context.addRoot(frameLayer);

		// FPS printing
		auto fpsLabel = context.getWidgetById("fpsLabel");
		auto fpsSlot = (FpsHelper* helper){fpsLabel["text"] = "FPS "~to!string(helper.fps);};
		fpsHelper.fpsUpdated.connect(fpsSlot);

		// Frames
		addHideHandler("infoFrame");
		addHideHandler("settingsFrame");

		setupFrameShowButton("showInfo", "infoFrame");
		setupFrameShowButton("showSettings", "settingsFrame");

		writeln("\n----------------------------- Load end -----------------------------\n");

		// ----------------------------- init chunks ---------------------------

		chunkMan.init();
		chunkMan.loadChunk(ChunkCoord(0, 0, 0));
	}

	override void update(double dt)
	{
		auto renderedLabel = context.getWidgetById("chunksRendered");
		renderedLabel["text"] = format("Chunks rendered %s", chunksRendered);
		chunksRendered = 0;

		fpsHelper.update(dt);
		timerManager.updateTimers(window.elapsedTime);
		context.update(dt);
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
		glUniformMatrix4fv(worldToCameraMatrixLoc, 1, GL_FALSE, fpsController.cameraMatrix);

		Matrix4f modelToWorldMatrix;
		foreach(Chunk* c; chunkMan.visibleChunks)
		{
			modelToWorldMatrix = translationMatrix!float(c.mesh.position);
			
			glUniformMatrix4fv(modelToWorldMatrixLoc, 1, GL_FALSE, cast(const float*)modelToWorldMatrix.arrayof);
			
			c.mesh.bind;
			c.mesh.render;
			++chunksRendered;
		}
		chunkShader.unbind;

		glDisable(GL_DEPTH_TEST);
		
		renderer.setColor(Color(0,0,0,1));
		//renderer.drawRect(Rect(width/2-7, height/2-1, 14, 2));
		//renderer.drawRect(Rect(width/2-1, height/2-7, 2, 14));
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
alias Vector!(short, 4) s4vec;

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
		s4vec vector;
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
}

// Chunk data
struct ChunkData
{
	/// null if homogeneous is true, or contains chunk data otherwise
	BlockType[] typeData;
	/// type of common block
	BlockType uniformType = 1; // Unknown block
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
	ChunkRegion visibleRegion;
	Chunk*[ulong] chunks;
	ChunkCoord observerPosition;
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

		ChunkRegion newRegion = ChunkRegion(chunkPos, visibleRegion.size);
		updateVisibleRegion(newRegion);
	}

	void updateVisibleRegion(ChunkRegion newRegion)
	{
		auto oldRegion = visibleRegion;
		visibleRegion = newRegion;

		// not done
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
}

// Stats
ulong numLoadChunkTasks;
ulong totalLoadedChunks;
ulong frameLoadedChunks;

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
	
	cd.typeData[0] = getBlock(
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

		cd.typeData[i] = getBlock(
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

	writefln("Chunk generated at %s uniform %s", chunk.coord, chunk.data.uniform);

	if (chunk.isVisible)
	{
		auto pool = taskPool();
		pool.put(task!chunkMeshWorker(chunk, cman));
	}

	++totalLoadedChunks;
	++frameLoadedChunks;
}

import anchovy.utils.noise.simplex;

// Gen single block
BlockType getBlock( int x, int y, int z)
{
	if ((Simplex.noise(cast(float)x/42, cast(float)z/42)*10 )>=y) return 2;
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
[0.0,0.6,0.0,
 0.0,0.6,0.0,
 0.0,0.6,0.0,
 0.0,0.6,0.0,
 0.0,0.4,0.0,
 0.0,0.8,0.0,];

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
		if(tx == -1) // west
		{
			return cman.blockTypes[ cNeigh[Side.west].getBlockType(chunkSize-1, cast(ubyte)ty, cast(ubyte)tz) ].isSideTransparent(side);
		}
		if(tx == 16) // east
		{
			return cman.blockTypes[ cNeigh[Side.east].getBlockType(0, cast(ubyte)ty, cast(ubyte)tz) ].isSideTransparent(side);
		}

		if(ty == -1) // bottom
		{
			return cman.blockTypes[ cNeigh[Side.bottom].getBlockType(cast(ubyte)tx, chunkSize-1, cast(ubyte)tz) ].isSideTransparent(side);
		}
		if(ty == 16) // top
		{
			return cman.blockTypes[ cNeigh[Side.top].getBlockType(cast(ubyte)tx, 0, cast(ubyte)tz) ].isSideTransparent(side);
		}

		if(tz == -1) // north
		{
			return cman.blockTypes[ cNeigh[Side.north].getBlockType(cast(ubyte)tx, cast(ubyte)ty, chunkSize-1) ].isSideTransparent(side);
		}
		if(tz == 16) // south
		{
			return cman.blockTypes[ cNeigh[Side.south].getBlockType(cast(ubyte)tx, cast(ubyte)ty, 0) ].isSideTransparent(side);
		}
		
		return cman.blockTypes[ chunk.getBlockType(cast(ubyte)tx, cast(ubyte)ty, cast(ubyte)tz) ].isSideTransparent(side);
	}
	
	ubyte sides = 0;
	ubyte sidenum = 0;
	byte[3] offset;

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
	chunk.mesh.position = vec3(coord.x * chunkSize,
							   coord.y * chunkSize,
							   coord.z * chunkSize);
	chunk.mesh.isDataDirty = true;
	chunk.hasMesh = true;

	writefln("Chunk mesh generated at %s", chunk.coord);
}