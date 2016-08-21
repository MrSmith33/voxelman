/*
 * A speed-improved simplex noise algorithm for 2D, 3D and 4D in Java.
 *
 * Based on example code by Stefan Gustavson (stegu@itn.liu.se).
 * Optimisations by Peter Eastman (peastman@drizzle.stanford.edu).
 * Better rank ordering method for 4D by Stefan Gustavson in 2012.
 *
 * This could be speeded up even further, but it's useful as it is.
 *
 * Version 2012-03-09
 *
 * This code was placed in the public domain by its original author,
 * Stefan Gustavson. You may use it as you see fit, but
 * attribution is appreciated.
 *
 * http://webstaff.itn.liu.se/~stegu/simplexnoise/SimplexNoise.java
 */

module voxelman.math.simplex;

import std.math;

// Simplex noise in 2D, 3D and 4D
struct SimplexNoise {
	// 2D simplex noise
	static double noise(double xin, double yin) pure @nogc nothrow {
		double n0, n1, n2; // Noise contributions from the three corners
		// Skew the input space to determine which simplex cell we're in
		double s = (xin+yin)*F2; // Hairy factor for 2D
		int i = fastfloor(xin+s);
		int j = fastfloor(yin+s);
		double t = (i+j)*G2;
		double X0 = i-t; // Unskew the cell origin back to (x,y) space
		double Y0 = j-t;
		double x0 = xin-X0; // The x,y distances from the cell origin
		double y0 = yin-Y0;
		// For the 2D case, the simplex shape is an equilateral triangle.
		// Determine which simplex we are in.
		int i1, j1; // Offsets for second (middle) corner of simplex in (i,j) coords
		if(x0>y0) {i1=1; j1=0;} // lower triangle, XY order: (0,0)->(1,0)->(1,1)
		else {i1=0; j1=1;}      // upper triangle, YX order: (0,0)->(0,1)->(1,1)
		// A step of (1,0) in (i,j) means a step of (1-c,-c) in (x,y), and
		// a step of (0,1) in (i,j) means a step of (-c,1-c) in (x,y), where
		// c = (3-sqrt(3))/6
		double x1 = x0 - i1 + G2; // Offsets for middle corner in (x,y) unskewed coords
		double y1 = y0 - j1 + G2;
		double x2 = x0 - 1.0 + 2.0 * G2; // Offsets for last corner in (x,y) unskewed coords
		double y2 = y0 - 1.0 + 2.0 * G2;
		// Work out the hashed gradient indices of the three simplex corners
		int ii = i & 255;
		int jj = j & 255;
		int gi0 = permMod12[ii+perm[jj]];
		int gi1 = permMod12[ii+i1+perm[jj+j1]];
		int gi2 = permMod12[ii+1+perm[jj+1]];
		// Calculate the contribution from the three corners
		double t0 = 0.5 - x0*x0-y0*y0;
		if(t0<0) n0 = 0.0;
		else {
			t0 *= t0;
			n0 = t0 * t0 * dot(grad3[gi0], x0, y0);  // (x,y) of grad3 used for 2D gradient
		}
		double t1 = 0.5 - x1*x1-y1*y1;
		if(t1<0) n1 = 0.0;
		else {
			t1 *= t1;
			n1 = t1 * t1 * dot(grad3[gi1], x1, y1);
		}
		double t2 = 0.5 - x2*x2-y2*y2;
		if(t2<0) n2 = 0.0;
		else {
			t2 *= t2;
			n2 = t2 * t2 * dot(grad3[gi2], x2, y2);
		}
		// Add contributions from each corner to get the final noise value.
		// The result is scaled to return values in the interval [-1,1].
		return 70.0 * (n0 + n1 + n2);
	}

	// 3D simplex noise
	static double noise(double xin, double yin, double zin) pure @nogc nothrow {
		double n0, n1, n2, n3; // Noise contributions from the four corners
		// Skew the input space to determine which simplex cell we're in
		double s = (xin+yin+zin)*F3; // Very nice and simple skew factor for 3D
		int i = fastfloor(xin+s);
		int j = fastfloor(yin+s);
		int k = fastfloor(zin+s);
		double t = (i+j+k)*G3;
		double X0 = i-t; // Unskew the cell origin back to (x,y,z) space
		double Y0 = j-t;
		double Z0 = k-t;
		double x0 = xin-X0; // The x,y,z distances from the cell origin
		double y0 = yin-Y0;
		double z0 = zin-Z0;
		// For the 3D case, the simplex shape is a slightly irregular tetrahedron.
		// Determine which simplex we are in.
		int i1, j1, k1; // Offsets for second corner of simplex in (i,j,k) coords
		int i2, j2, k2; // Offsets for third corner of simplex in (i,j,k) coords
		if(x0>=y0) {
			if(y0>=z0)
				{ i1=1; j1=0; k1=0; i2=1; j2=1; k2=0; } // X Y Z order
				else if(x0>=z0) { i1=1; j1=0; k1=0; i2=1; j2=0; k2=1; } // X Z Y order
				else { i1=0; j1=0; k1=1; i2=1; j2=0; k2=1; } // Z X Y order
			}
		else { // x0<y0
			if(y0<z0) { i1=0; j1=0; k1=1; i2=0; j2=1; k2=1; } // Z Y X order
			else if(x0<z0) { i1=0; j1=1; k1=0; i2=0; j2=1; k2=1; } // Y Z X order
			else { i1=0; j1=1; k1=0; i2=1; j2=1; k2=0; } // Y X Z order
		}
		// A step of (1,0,0) in (i,j,k) means a step of (1-c,-c,-c) in (x,y,z),
		// a step of (0,1,0) in (i,j,k) means a step of (-c,1-c,-c) in (x,y,z), and
		// a step of (0,0,1) in (i,j,k) means a step of (-c,-c,1-c) in (x,y,z), where
		// c = 1/6.
		double x1 = x0 - i1 + G3; // Offsets for second corner in (x,y,z) coords
		double y1 = y0 - j1 + G3;
		double z1 = z0 - k1 + G3;
		double x2 = x0 - i2 + 2.0*G3; // Offsets for third corner in (x,y,z) coords
		double y2 = y0 - j2 + 2.0*G3;
		double z2 = z0 - k2 + 2.0*G3;
		double x3 = x0 - 1.0 + 3.0*G3; // Offsets for last corner in (x,y,z) coords
		double y3 = y0 - 1.0 + 3.0*G3;
		double z3 = z0 - 1.0 + 3.0*G3;
		// Work out the hashed gradient indices of the four simplex corners
		int ii = i & 255;
		int jj = j & 255;
		int kk = k & 255;
		int gi0 = permMod12[ii+perm[jj+perm[kk]]];
		int gi1 = permMod12[ii+i1+perm[jj+j1+perm[kk+k1]]];
		int gi2 = permMod12[ii+i2+perm[jj+j2+perm[kk+k2]]];
		int gi3 = permMod12[ii+1+perm[jj+1+perm[kk+1]]];
		// Calculate the contribution from the four corners
		double t0 = 0.6 - x0*x0 - y0*y0 - z0*z0;
		if(t0<0) n0 = 0.0;
		else {
			t0 *= t0;
			n0 = t0 * t0 * dot(grad3[gi0], x0, y0, z0);
		}
		double t1 = 0.6 - x1*x1 - y1*y1 - z1*z1;
		if(t1<0) n1 = 0.0;
		else {
			t1 *= t1;
			n1 = t1 * t1 * dot(grad3[gi1], x1, y1, z1);
		}
		double t2 = 0.6 - x2*x2 - y2*y2 - z2*z2;
		if(t2<0) n2 = 0.0;
		else {
			t2 *= t2;
			n2 = t2 * t2 * dot(grad3[gi2], x2, y2, z2);
		}
		double t3 = 0.6 - x3*x3 - y3*y3 - z3*z3;
		if(t3<0) n3 = 0.0;
		else {
			t3 *= t3;
			n3 = t3 * t3 * dot(grad3[gi3], x3, y3, z3);
		}
		// Add contributions from each corner to get the final noise value.
		// The result is scaled to stay just inside [-1,1]
		return 32.0*(n0 + n1 + n2 + n3);
	}

	// 4D simplex noise, better simplex rank ordering method 2012-03-09
	static double noise(double x, double y, double z, double w) pure @nogc nothrow {

		double n0, n1, n2, n3, n4; // Noise contributions from the five corners
		// Skew the (x,y,z,w) space to determine which cell of 24 simplices we're in
		double s = (x + y + z + w) * F4; // Factor for 4D skewing
		int i = fastfloor(x + s);
		int j = fastfloor(y + s);
		int k = fastfloor(z + s);
		int l = fastfloor(w + s);
		double t = (i + j + k + l) * G4; // Factor for 4D unskewing
		double X0 = i - t; // Unskew the cell origin back to (x,y,z,w) space
		double Y0 = j - t;
		double Z0 = k - t;
		double W0 = l - t;
		double x0 = x - X0;  // The x,y,z,w distances from the cell origin
		double y0 = y - Y0;
		double z0 = z - Z0;
		double w0 = w - W0;
		// For the 4D case, the simplex is a 4D shape I won't even try to describe.
		// To find out which of the 24 possible simplices we're in, we need to
		// determine the magnitude ordering of x0, y0, z0 and w0.
		// Six pair-wise comparisons are performed between each possible pair
		// of the four coordinates, and the results are used to rank the numbers.
		int rankx = 0;
		int ranky = 0;
		int rankz = 0;
		int rankw = 0;
		if(x0 > y0) rankx++; else ranky++;
		if(x0 > z0) rankx++; else rankz++;
		if(x0 > w0) rankx++; else rankw++;
		if(y0 > z0) ranky++; else rankz++;
		if(y0 > w0) ranky++; else rankw++;
		if(z0 > w0) rankz++; else rankw++;
		int i1, j1, k1, l1; // The integer offsets for the second simplex corner
		int i2, j2, k2, l2; // The integer offsets for the third simplex corner
		int i3, j3, k3, l3; // The integer offsets for the fourth simplex corner
		// [rankx, ranky, rankz, rankw] is a 4-vector with the numbers 0, 1, 2 and 3
		// in some order. We use a thresholding to set the coordinates in turn.
		// Rank 3 denotes the largest coordinate.
		i1 = rankx >= 3 ? 1 : 0;
		j1 = ranky >= 3 ? 1 : 0;
		k1 = rankz >= 3 ? 1 : 0;
		l1 = rankw >= 3 ? 1 : 0;
		// Rank 2 denotes the second largest coordinate.
		i2 = rankx >= 2 ? 1 : 0;
		j2 = ranky >= 2 ? 1 : 0;
		k2 = rankz >= 2 ? 1 : 0;
		l2 = rankw >= 2 ? 1 : 0;
		// Rank 1 denotes the second smallest coordinate.
		i3 = rankx >= 1 ? 1 : 0;
		j3 = ranky >= 1 ? 1 : 0;
		k3 = rankz >= 1 ? 1 : 0;
		l3 = rankw >= 1 ? 1 : 0;
		// The fifth corner has all coordinate offsets = 1, so no need to compute that.
		double x1 = x0 - i1 + G4; // Offsets for second corner in (x,y,z,w) coords
		double y1 = y0 - j1 + G4;
		double z1 = z0 - k1 + G4;
		double w1 = w0 - l1 + G4;
		double x2 = x0 - i2 + 2.0*G4; // Offsets for third corner in (x,y,z,w) coords
		double y2 = y0 - j2 + 2.0*G4;
		double z2 = z0 - k2 + 2.0*G4;
		double w2 = w0 - l2 + 2.0*G4;
		double x3 = x0 - i3 + 3.0*G4; // Offsets for fourth corner in (x,y,z,w) coords
		double y3 = y0 - j3 + 3.0*G4;
		double z3 = z0 - k3 + 3.0*G4;
		double w3 = w0 - l3 + 3.0*G4;
		double x4 = x0 - 1.0 + 4.0*G4; // Offsets for last corner in (x,y,z,w) coords
		double y4 = y0 - 1.0 + 4.0*G4;
		double z4 = z0 - 1.0 + 4.0*G4;
		double w4 = w0 - 1.0 + 4.0*G4;
		// Work out the hashed gradient indices of the five simplex corners
		int ii = i & 255;
		int jj = j & 255;
		int kk = k & 255;
		int ll = l & 255;
		int gi0 = perm[ii+perm[jj+perm[kk+perm[ll]]]] % 32;
		int gi1 = perm[ii+i1+perm[jj+j1+perm[kk+k1+perm[ll+l1]]]] % 32;
		int gi2 = perm[ii+i2+perm[jj+j2+perm[kk+k2+perm[ll+l2]]]] % 32;
		int gi3 = perm[ii+i3+perm[jj+j3+perm[kk+k3+perm[ll+l3]]]] % 32;
		int gi4 = perm[ii+1+perm[jj+1+perm[kk+1+perm[ll+1]]]] % 32;
		// Calculate the contribution from the five corners
		double t0 = 0.6 - x0*x0 - y0*y0 - z0*z0 - w0*w0;
		if(t0<0) n0 = 0.0;
		else {
			t0 *= t0;
			n0 = t0 * t0 * dot(grad4[gi0], x0, y0, z0, w0);
		}
	 double t1 = 0.6 - x1*x1 - y1*y1 - z1*z1 - w1*w1;
		if(t1<0) n1 = 0.0;
		else {
			t1 *= t1;
			n1 = t1 * t1 * dot(grad4[gi1], x1, y1, z1, w1);
		}
	 double t2 = 0.6 - x2*x2 - y2*y2 - z2*z2 - w2*w2;
		if(t2<0) n2 = 0.0;
		else {
			t2 *= t2;
			n2 = t2 * t2 * dot(grad4[gi2], x2, y2, z2, w2);
		}
	 double t3 = 0.6 - x3*x3 - y3*y3 - z3*z3 - w3*w3;
		if(t3<0) n3 = 0.0;
		else {
			t3 *= t3;
			n3 = t3 * t3 * dot(grad4[gi3], x3, y3, z3, w3);
		}
	 double t4 = 0.6 - x4*x4 - y4*y4 - z4*z4 - w4*w4;
		if(t4<0) n4 = 0.0;
		else {
			t4 *= t4;
			n4 = t4 * t4 * dot(grad4[gi4], x4, y4, z4, w4);
		}
		// Sum up and scale the result to cover the range [-1,1]
		return 27.0 * (n0 + n1 + n2 + n3 + n4);
	}
}

private:

// Skewing and unskewing factors for 2, 3, and 4 dimensions
enum double F2 = 0.5 * (sqrt(3.0) - 1.0);
enum double G2 = (3.0 - sqrt(3.0)) / 6.0;
enum double F3 = 1.0 / 3.0;
enum double G3 = 1.0 / 6.0;
enum double F4 = (sqrt(5.0) - 1.0) / 4.0;
enum double G4 = (5.0 - sqrt(5.0)) / 20.0;

pure const @nogc nothrow:
pragma(inline, true):

// This method is a *lot* faster than using (int)floor(x)
int fastfloor(double x) {
	int xi = cast(int)x;
	return x<xi ? xi-1 : xi;
}

double dot(const byte[] g, double x, const double y) {
	return g[0]*x + g[1]*y;
}

double dot(const byte[] g, double x, double y, double z) {
	return g[0]*x + g[1]*y + g[2]*z;
}

double dot(const byte[] g, double x, double y, double z, double w) {
	return g[0]*x + g[1]*y + g[2]*z + g[3]*w;
}

immutable byte[3][12] grad3 = [
	[1, 1, 0], [-1, 1, 0], [1,-1, 0], [-1,-1, 0],
	[1, 0, 1], [-1, 0, 1], [1, 0,-1], [-1, 0,-1],
	[0, 1, 1], [ 0,-1, 1], [0, 1,-1], [ 0,-1,-1]];
immutable byte[4][32] grad4 = [
	[ 0, 1, 1, 1], [ 0, 1, 1,-1], [ 0, 1,-1, 1], [ 0, 1,-1,-1],
	[ 0,-1, 1, 1], [ 0,-1, 1,-1], [ 0,-1,-1, 1], [ 0,-1,-1,-1],
	[ 1, 0, 1, 1], [ 1, 0, 1,-1], [ 1, 0,-1, 1], [ 1, 0,-1,-1],
	[-1, 0, 1, 1], [-1, 0, 1,-1], [-1, 0,-1, 1], [-1, 0,-1,-1],
	[ 1, 1, 0, 1], [ 1, 1, 0,-1], [ 1,-1, 0, 1], [ 1,-1, 0,-1],
	[-1, 1, 0, 1], [-1, 1, 0,-1], [-1,-1, 0, 1], [-1,-1, 0,-1],
	[ 1, 1, 1, 0], [ 1, 1,-1, 0], [ 1,-1, 1, 0], [ 1,-1,-1, 0],
	[-1, 1, 1, 0], [-1, 1,-1, 0], [-1,-1, 1, 0], [-1,-1,-1, 0]];

immutable ushort[512] perm = [
	151,160,137,91, 90,15,131,13,201, 95,96, 53,194,233,7,225,140, 36,103,30,69,
	142, 8, 99,37,240,21,10,23, 190,6,148,247,120,234, 75, 0, 26,197,62, 94,252,
	219,203,117, 35,11,32, 57,177,33, 88,237,149, 56,87,174, 20,125,136,171,168,
	68,175, 74,165,71,134,139, 48,27,166,77,146,158,231, 83,111,229,122, 60,211,
	133,230,220,105, 92,41,55,46,245, 40,244,102,143, 54,65,25, 63,161,1,216,80,
	73,209, 76,132,187,208, 89, 18,169,200,196,135,130,116, 188,159, 86,164,100,
	109,198,173,186, 3,64, 52,217,226,250,124,123, 5,202, 38,147,118,126,255,82,
	85,212, 207,206,59,227,47, 16,58,17, 182,189,28,42,223,183,170, 213,119,248,
	152, 2,44,154,163, 70,221,153,101,155,167, 43,172, 9,129, 22, 39,253, 19,98,
	108,110, 79,113, 224,232, 178,185,112, 104,218,246, 97,228, 251, 34,242,193,
	238,210,144, 12,191,179,162,241, 81, 51,145,235,249, 14,239,107, 49,192,214,
	31,181,199, 106,157,184, 84,204,176,115,121, 50, 45,127, 4,150, 254,138,236,
	205, 93, 222,114, 67, 29, 24, 72,243, 141,128, 195, 78, 66,215, 61, 156,180,

	151,160,137,91, 90,15,131,13,201, 95,96, 53,194,233,7,225,140, 36,103,30,69,
	142, 8, 99,37,240,21,10,23, 190,6,148,247,120,234, 75, 0, 26,197,62, 94,252,
	219,203,117, 35,11,32, 57,177,33, 88,237,149, 56,87,174, 20,125,136,171,168,
	68,175, 74,165,71,134,139, 48,27,166,77,146,158,231, 83,111,229,122, 60,211,
	133,230,220,105, 92,41,55,46,245, 40,244,102,143, 54,65,25, 63,161,1,216,80,
	73,209, 76,132,187,208, 89, 18,169,200,196,135,130,116, 188,159, 86,164,100,
	109,198,173,186, 3,64, 52,217,226,250,124,123, 5,202, 38,147,118,126,255,82,
	85,212, 207,206,59,227,47, 16,58,17, 182,189,28,42,223,183,170, 213,119,248,
	152, 2,44,154,163, 70,221,153,101,155,167, 43,172, 9,129, 22, 39,253, 19,98,
	108,110, 79,113, 224,232, 178,185,112, 104,218,246, 97,228, 251, 34,242,193,
	238,210,144, 12,191,179,162,241, 81, 51,145,235,249, 14,239,107, 49,192,214,
	31,181,199, 106,157,184, 84,204,176,115,121, 50, 45,127, 4,150, 254,138,236,
	205, 93, 222,114, 67, 29, 24, 72,243, 141,128, 195, 78, 66,215, 61, 156,180];

// permMod12[i] = (short)(perm[i] % 12);
immutable ushort[512] permMod12 = [
	7,4,5,7,6,3,11,1,9,11,0,5,2,5,7,9,8,0,7,6,9,10,8,3,1,0,9,10,11,10,6,4,7,0,6,
	3,0,2,5,2,10,0,3,11, 9,11,11,8,9,9,9,4,9,5,8,3,6,8,5,4,3,0,8,7,2,9,11,2,7,0,
	3,10,5,2,2,3,11,3,1,2,0,7,1,2,4,9,8,5,7,10,5,4,4,6,11,6,5,1,3,5,1,0,8,1,5,4,
	0,7,4,5,6,1,8,4,3,10,8,8,3,2,8,4,1,6,5,6,3,4,4, 1,10,10,4,3,5,10,2,3,10,6,3,
	10,1,8,3,2,11,11,11,4,10,5,2,9,4,6,7,3,2,9,11,8,8,2,8,10,7,10,5,9,5,11,11,7,
	4,9,9,10,3,1,7,2,0,2,7,5,8, 4,10,5,4,8,2,6,1,0,11,10,2,1,10,6,0,0,11,11,6,1,
	9,3,1,7,9,2,11,11,1,0,10,7,1,7,10,1,4,0,0,8,7,1,2,9,7,4,6,2,6,8,1,9,6,6,7,5,
	0,0,3,9,8,3,6,6,11,1,0,0,7,4,5,7,6,3,11,1,9,11,0,5,2,5,7,9,8,0,7,6,9,10,8,3,
	1,0,9,10,11,10,6,4,7,0,6,3,0,2,5,2,10,0,3,11,9,11,11,8,9, 9,9,4,9,5,8,3,6,8,
	5,4,3,0,8,7,2,9,11,2,7,0,3,10,5,2,2,3,11,3,1,2,0,7,1,2,4,9,8,5,7,10,5,4,4,6,
	11,6,5,1,3, 5,1,0,8,1,5,4,0, 7,4,5,6,1,8,4,3,10,8,8,3,2,8,4,1,6,5,6,3,4,4,1,
	10,10,4,3,5,10,2,3,10,6,3,10,1,8,3,2,11,11,11,4,10,5,2,9,4,6,7,3,2,9,11,8,8,
	2,8,10,7,10,5,9,5,11,11,7,4,9,9,10,3,1,7,2, 0,2,7,5,8,4,10,5,4,8,2,6,1,0,11,
	10,2,1,10,6,0,0,11,11,6,1,9,3,1,7,9,2,11,11,1,0,10,7,1,7,10,1,4,0,0,8,7,1,2,
	9,7,4,6,2,6,8,1,9,6,6,7,5,0,0,3,9,8,3,6,6,11,1,0,0];
