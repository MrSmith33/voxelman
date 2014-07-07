#version 330

layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;

smooth out vec4 theColor;

uniform mat4 cameraToClipMatrix;
uniform mat4 worldToCameraMatrix;
uniform mat4 modelToWorldMatrix;

void main()
{
	gl_Position = cameraToClipMatrix * worldToCameraMatrix * modelToWorldMatrix * position;
	theColor = color;
}