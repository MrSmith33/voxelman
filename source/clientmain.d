module voxelman.clientmain;


import voxelman.client.app;
import anchovy.gui;

void main(string[] args)
{
	// BUG test
	//import dlib.geometry.frustum;
	//Frustum f;
	//Frustum f2;
	//f2 = f;

	auto app = new ClientApp(uvec2(1280, 720), "Voxel engine client test");
	app.run(args);
}