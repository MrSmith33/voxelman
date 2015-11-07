#version 330

smooth in vec4 theColor;
//in vec3 normal;

out vec4 outputColor;

//const vec3 lightDir = vec3(0.0,-1.0,0.0);

void main()
{
	//vec4(gl_FragCoord.w,gl_FragCoord.w,gl_FragCoord.w,1);
	outputColor = theColor;
}
