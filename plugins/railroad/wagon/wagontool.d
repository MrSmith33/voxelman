/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.wagon.wagontool;

import dlib.geometry.plane;
import voxelman.log;
import voxelman.math;

import voxelman.blockentity.blockentityman;

import voxelman.edit.plugin;
import voxelman.edit.tools.itool;

import voxelman.graphics.plugin;
import voxelman.net.plugin;

import voxelman.world.blockentity;
import voxelman.world.clientworld;
import voxelman.world.storage;
import voxelman.worldinteraction.plugin;

import railroad.rail.utils;
import railroad.wagon.packets;
import railroad.wagon.wagon;
import voxelman.world.mesh.utils : FaceSide, oppFaceSides;

final class WagonTool : ITool
{
	ClientWorld clientWorld;
	BlockEntityManager blockEntityManager;
	NetClientPlugin connection;
	WorldInteractionPlugin worldInteraction;
	GraphicsPlugin graphics;

	// need to check for emptiness
	RailData data;
	RailPos railPos;
	bool placeAllowed;
	vec3 preciseHitPos;

	float wagonAxisDistance = 8;
	float wagonRotation = 0;

	this(ClientWorld clientWorld, BlockEntityManager blockEntityManager,
		NetClientPlugin connection, WorldInteractionPlugin worldInteraction,
		GraphicsPlugin graphics)
	{
		this.clientWorld = clientWorld;
		this.blockEntityManager = blockEntityManager;
		this.connection = connection;
		this.worldInteraction = worldInteraction;
		this.graphics = graphics;
		name = "entity.wagon_tool";
	}

	override void onUpdate()
	{
		auto plane = Plane(vec3(0,1,0), worldInteraction.hitPosition.y);
		vec3 camPos = worldInteraction.cameraPos;
		plane.intersectsLine(camPos, camPos+worldInteraction.cameraTraget, preciseHitPos);
		preciseHitPos.y = worldInteraction.hitPosition.y;
		graphics.debugText.putfln("hit %s", worldInteraction.hitPosition);
		graphics.debugText.putfln("precise hit %s", preciseHitPos);

		railPos = RailPos(worldInteraction.blockPos);
		data = railAt(railPos);
	}

	private RailData railAt(RailPos pos)
	{
		ushort targetEntityId = blockEntityManager.getId("rail");
		return getRailAt(pos, targetEntityId, clientWorld.worldAccess, clientWorld.entityAccess);
	}

	// returns q the closest point to p on the line segment from a to b
	vec3 project_point_to_line_segment(vec3 a, vec3 b, vec3 p)
	{
		// vector from a to b
		vec3 AB = b - a;

		// squared distance from a to b
		float AB_squared = dot(AB, AB);

		if(AB_squared == 0)
		{
			// a and b are the same point
			return a;
		}
		else
		{
			// vector from a to p
			vec3 Ap = p - a;

			// from http://stackoverflow.com/questions/849211/
			// Consider the line extending the segment, parameterized as a + t (b - a)
			// We find projection of point p onto the line.
			// It falls where t = [(p-a) . (b-a)] / |b-a|^2
			float t = dot(Ap, AB) / AB_squared;

			if (t < 0.0f)
			{
				// "Before" a on the line, just return a
				return a;
			}
			else if (t > 1.0f)
			{
				// "After" b on the line, just return b
				return b;
			}
			else
			{
				// projection lines "inbetween" a and b on the line
				return a + t * AB;
			}
		}
	}

	float point_time_on_line_segment(vec3 a, vec3 b, vec3 p)
	{
		vec3 AB = b - a;
		float AB_squared = dot(AB, AB);
		if(AB_squared == 0) return 0;
		else return dot(p - a, AB) / AB_squared;
	}

	vec3 pointSize = vec3(0.5f,0.5f,0.5f);
	vec3 pointOffset = vec3(0.25f,0.25f,0.25f);

	// Assumes non-empty rail
	// Virtual wagon is placed at user's cursor position and has 'wagonRotation' rotation.
	// The goal is to find positions of wagon's ends to be placed.
	// Algorithm:
	// 1. For hovered rail tile find closest segment
	// 2. For best candidate, for each end calc:
	//    - position and rail (vec3, RailPos, RailSegment, side of tile and segment end index)
	//    - error (diff between end's position and virtual wagon position)
	// 3. Iteratively try to build wagon placement closest to virtual wagon
	// 3.1. If we hit the end of segment when placing one of the ends,
	//      look into attached segments, replacing current selected segment with closer one
	//      Repeat until we can place two ends
	vec3[2] findWagonPlacement()
	{
		assert(!data.empty);

		vec3 railWorldPos = vec3(railPos.toBlockWorldPos.xyz);
		// wagon center
		vec3 wagonC = vec3(preciseHitPos);

		vec3 vertOff = vec3(0,1,0);
		vec3 wagonVector = vec3(cos(wagonRotation), 0, sin(wagonRotation));
		vec3 wagonA = vertOff + wagonC - wagonVector * wagonAxisDistance/2;
		vec3 wagonB = vertOff + wagonC + wagonVector * wagonAxisDistance/2;
		vec3[2] wagonPoints = [wagonA-vertOff, wagonB-vertOff];
		graphics.debugText.putfln(" wagA %s wagB %s", wagonPoints[0], wagonPoints[1]);

		// Shadow wagon
		graphics.debugBatch.putLine(wagonA, wagonB, Color4ub(0,0,0,64));
		graphics.debugBatch.putCube(wagonA-pointOffset, pointSize, Color4ub(0,0,0,64), true);
		graphics.debugBatch.putCube(wagonB-pointOffset, pointSize, Color4ub(0,0,0,64), true);
		graphics.debugText.putfln("wagon rotation %.1f", radtodeg(wagonRotation));

		vec3[2] resultPos;
		vec3[2] resultInnerPos;
		RailPos[2] resultRail = [railPos, railPos];
		RailSegment[2] resultSegment;
		FaceSide[2] resultSides;
		size_t[2] resultOuterIndex;
		bool[2] canExtend = [true, true];

		// errors say how far is calculated position to the given one
		float segmentError = float.infinity;
		float[2] errors;

		// Find best central segment
		foreach(i, segment; data.getSegments)
		{
			FaceSide[2] sides = segmentInfos[segment].sides;
			// Set first approximation
			vec3 railA = railWorldPos + railTileConnectionPoints[sides[0]]-vec3(0f,0.5f,0f);
			vec3 railB = railWorldPos + railTileConnectionPoints[sides[1]]-vec3(0f,0.5f,0f);
			//graphics.debugText.putfln(" railA %s railB %s", railA, railB);

			float errorAA = distancesqr(railA, wagonPoints[0]);
			float errorBB = distancesqr(railB, wagonPoints[1]);

			float errorAB = distancesqr(railA, wagonPoints[1]);
			float errorBA = distancesqr(railB, wagonPoints[0]);

			float[2] newErrors;
			float newError;

			float error0 = errorAA + errorBB;
			float error1 = errorAB + errorBA;

			if (error0 < error1)
			{
				newError = error0;
				newErrors = [errorAA, errorBB];
			}
			else
			{
				newError = error1;
				newErrors = [errorAB, errorBA];
			}

			//graphics.debugText.putfln(" AA %s AB %s BB %s BA %s", errorAA, errorAB, errorBB, errorBA);
			//graphics.debugText.putfln(" error of %s is %.1f", segment, newError);

			void setSegment(int idx0, int idx1)
			{
				resultPos[idx0] = railA;
				resultPos[idx1] = railB;
				resultInnerPos[idx0] = railB;
				resultInnerPos[idx1] = railA;
				resultSides[idx0] = sides[0];
				resultSides[idx1] = sides[1];
				errors[idx0] = newErrors[0];
				errors[idx1] = newErrors[1];
				segmentError = newError;
				resultOuterIndex[idx0] = 0;
				resultOuterIndex[idx1] = 1;
				resultSegment = [segment, segment];
			}

			if (newError < segmentError)
			{
				if (error0 < error1) setSegment(0, 1);
				else setSegment(1, 0);
			}
		}

		immutable float wagonLenSqr = wagonAxisDistance * wagonAxisDistance;

		// Returns true if extension was successfull
		// Returns false otherwise (i.e. no rail in given direction)
		bool extendRails(size_t nextIdx)
		{
			RailPos adjacentPos = resultRail[nextIdx].posInDirection(resultSides[nextIdx]);
			RailData adjacentData = railAt(adjacentPos);
			FaceSide connectedViaSide = oppFaceSides[resultSides[nextIdx]];
			vec3 adjRailWorldPos = vec3(adjacentPos.toBlockWorldPos.xyz);
			graphics.debugText.putfln(" - extend %s in %s at %s", nextIdx, resultSides[nextIdx], adjacentPos);

			float pointError = float.infinity;

			bool success = false;

			// TODO smooth connection checking
			foreach(adjSegment; adjacentData.getSegments)
			{
				graphics.debugText.putfln("   - segm side %s conn %s", adjSegment, segmentInfos[adjSegment].sideConnections[connectedViaSide]);
				if (segmentInfos[adjSegment].sideConnections[connectedViaSide])
				{
					size_t innerIndex = segmentInfos[adjSegment].sideIndicies[connectedViaSide];
					size_t outerIndex = 1 - innerIndex;
					FaceSide[2] sides = segmentInfos[adjSegment].sides;
					vec3 railInnerEnd = adjRailWorldPos + railTileConnectionPoints[sides[innerIndex]]-vec3(0f,0.5f,0f);
					vec3 railOuterEnd = adjRailWorldPos + railTileConnectionPoints[sides[outerIndex]]-vec3(0f,0.5f,0f);
					vec3 closestPoint = project_point_to_line_segment(railInnerEnd, railOuterEnd, wagonPoints[nextIdx]);
					float endError = distancesqr(closestPoint, wagonPoints[nextIdx]);

					void setPoint()
					{
						// set attributes of outer end of the rail
						resultOuterIndex[nextIdx] = outerIndex;
						graphics.debugText.putfln("   - set side %s", outerIndex);
						resultInnerPos[nextIdx] = resultPos[nextIdx];
						resultPos[nextIdx] = railOuterEnd;
						resultRail[nextIdx] = adjacentPos;
						resultSides[nextIdx] = sides[outerIndex];
						segmentError = errors[1-nextIdx] + endError;
						errors[nextIdx] = endError;
						pointError = endError;
						resultSegment[nextIdx] = adjSegment;
						success = true;
					}

					if (endError < pointError) setPoint();
				}
			}

			graphics.debugText.putfln(" - success %s", success);

			canExtend[nextIdx] = success;

			return success;
		}

		// Reports true when wagon position is found
		// Otherwise a new segment needs to be attached to one of the ends
		bool tryPlaceWagon()
		{
			// Can potentially place
			if (wagonLenSqr <= distancesqr(resultPos[0], resultPos[1]))
			{
				graphics.debugText.putfln(" - place success %s <= %s", wagonLenSqr, distancesqr(resultPos[0], resultPos[1]));

				vec3 inner0 = resultInnerPos[0];
				vec3 outer0 = resultPos[0];
				vec3 inner1 = resultInnerPos[1];
				vec3 outer1 = resultPos[1];

				if (resultOuterIndex[0] == 0) swap(inner0, outer0);
				if (resultOuterIndex[1] == 0) swap(inner1, outer1);

				graphics.debugBatch.putCube(vertOff*1.5f + outer0-pointOffset, pointSize, Color4ub(0,100,100,255), true);
				graphics.debugBatch.putCube(vertOff*1.5f + inner0-pointOffset, pointSize, Color4ub(0,200,200,255), true);
				graphics.debugBatch.putCube(vertOff*2.5f + inner1-pointOffset, pointSize, Color4ub(100,100,0,255), true);
				graphics.debugBatch.putCube(vertOff*2.5f + outer1-pointOffset, pointSize, Color4ub(200,200,0,255), true);

				float pos0t = equation2(inner0.xz, outer0.xz, preciseHitPos.xz, wagonAxisDistance/2.0);
				vec3 pos0 = lerp(inner0, outer0, pos0t);

				graphics.debugText.putfln("lerp 0 %s ext %s", pos0t, canExtend[0]);
				if ((pos0t < 0 || pos0t > 1) && canExtend[0])
				{
					extendRails(0);
					return false;
				}

				float pos1t = equation2(inner1.xz, outer1.xz, pos0.xz, wagonAxisDistance);
				vec3 pos1 = lerp(inner1, outer1, pos1t);

				graphics.debugText.putfln("lerp 1 %s ext %s", pos1t, canExtend[1]);
				if ((pos1t < 0 || pos1t > 1) && canExtend[1])
				{
					extendRails(1);
					return false;
				}

				resultPos = [pos0, pos1];
				graphics.debugText.putfln("lerp 0 %s 1 %s", pos0t, pos1t);
				graphics.debugText.putfln("final pos %s", resultPos);
				return true;
			}
			else
			{
				// Extend points to adjacent segments as nesessary
				size_t nextIdx;
				// fail, need more space
				// extend in direction closer to wagon center
				graphics.debugText.putfln(" - place fail");
				if (distancesqr(wagonC, resultPos[0]) < distancesqr(wagonC, resultPos[1]))
				{
					if (!extendRails(0)) extendRails(1);
				}
				else
				{
					if (!extendRails(1)) extendRails(0);
				}
				return false;
			}
		}

		size_t iters;
		while(!tryPlaceWagon()) {
			if (iters++ > 10) break;
		}

		// Best first segment
		graphics.debugBatch.putLine(vertOff + resultPos[0], vertOff + resultPos[1], Color4ub(0,255,0,255));
		graphics.debugBatch.putCube(vertOff + resultPos[0]-pointOffset, pointSize, Color4ub(255,0,0,255), true);
		graphics.debugBatch.putCube(vertOff + resultPos[1]-pointOffset, pointSize, Color4ub(0,255,0,255), true);
		return resultPos;
	}

	override void onRender(GraphicsPlugin renderer)
	{
		void drawRailsAt(vec3 railWorldPos, RailSegment segment, Color4ub color)
		{
			FaceSide[2] sides = segmentInfos[segment].sides;
			vec3 pos0 = railWorldPos + railTileConnectionPoints[sides[0]];
			vec3 pos1 = railWorldPos + railTileConnectionPoints[sides[1]];
			renderer.debugBatch.putLine(pos0, pos1, color);
		}

		void drawSegments()
		{
			vec3 railWorldPos = vec3(railPos.toBlockWorldPos.xyz);

			// Segments of hovered rail tile
			foreach(i, segment; data.getSegments)
			{
				enum layerDist = 0.25f;
				drawRailsAt(railWorldPos + vec3(0, i*layerDist, 0), segment, colorsArray[i+2]);

				FaceSide[2] sides = segmentInfos[segment].sides;

				foreach(side; sides)
				{
					RailPos adjacentPos = railPos.posInDirection(side);
					RailData adjacentData = railAt(adjacentPos);

					// side with which adjacent segment connects to main segment
					FaceSide connectedViaSide = oppFaceSides[side];

					// Process all segments that connect to main segment
					foreach(adjSegment; adjacentData.getSegments)
					if (segmentInfos[adjSegment].sideConnections[connectedViaSide])
					{
						vec3 adjRailWorldPos = vec3(adjacentPos.toBlockWorldPos.xyz);
						drawRailsAt(adjRailWorldPos + vec3(0, i*layerDist, 0), adjSegment, colorsArray[i+2]);
					}
				}
			}
		}

		if (!data.empty)
		{
			graphics.debugText.putfln("hover %s", railPos);
			vec3[2] ends = findWagonPlacement();
			float angle = -atan2(ends[1].z - ends[0].z, ends[1].x - ends[0].x);
			auto quat = rotationQuaternion(vec3(0,1,0), angle);
			vec3 wagonCenter = (ends[0] + ends[1]) * 0.5f + vec3(0,1,0);
			enum wagonWidth = 3.0f;
			enum wagonHeight = 4.0f;
			float wagonLength = wagonAxisDistance + 4.0f;

			vec3 wagonSize = vec3(wagonLength, wagonHeight, wagonWidth);
			vec3 centerOffset = -vec3(wagonSize.x*0.5f, 0, wagonSize.z*0.5f);

			import voxelman.geometry.cubeutils;
			putFilledBlock(renderer.debugBatch.triBuffer, wagonCenter, wagonSize, -vec3(0.5,0.5,0.5), quat, Color4ub(128, 128, 128, 255));

			//drawSegments();
		}
	}

	override void onSecondaryActionRelease()
	{
		if (!data.empty) connection.send(CreateWagonPacket(railPos));
	}

	override void onRotateAction() {
		wagonRotation += 2*PI / 8;
		wagonRotation %= 2*PI;
	}
}

float equation2(vec2 p1, vec2 p2, vec2 circlePos, float radius)
{
	return equation(p1 - circlePos, p2 - circlePos, radius);
}

// for a circle at 0,0. calculate its intersection with a line segment
// described with p1, p2 and return a position along the line as [0; 1]
float equation(vec2 p1, vec2 p2, float radius)
{
	float dx = (p2.x - p1.x);
	float dy = (p2.y - p1.y);
	float a = dx*dx + dy*dy;
	float b = 2*(dy*p1.y + dx*p1.x);
	float c = p1.x*p1.x + p1.y*p1.y - radius*radius;
	float d = b*b - 4*a*c;
	float sqrt_d = sqrt(d);
	float t1 = (-b + sqrt_d) / (2*a);
	float t2 = (-b - sqrt_d) / (2*a);
	if (std_abs(t2 - 0.5f) < std_abs(t1 - 0.5f)) return t2;
	return t1;
	//if (t1 < 0 || t1 > 1) return t2;
	//return t1;
}

// t position on rail, R length between wagon points
// x₁y₁, x₂y₂ rail ends
// (1) x² + y² = R²
// (2) x = x₁ + t(x₂-x₁)
// (3) y = y₁ + t(y₂-y₁)
// We substitute (2) and (3) into (1) and get quadratic equation
// t²((x₂-x₁)² + (y₂-y₁)²) + t2((y₂-y₁)y₂ + (x₁-x₁)x₂) + x₁ + y₁ - R² = 0
// solve for t

// a = (x2 - x1)^2 + (y2 - y1)^2;
// b = 2 * ((y2 - y1)*y1 + (x2 - x1)*x1);
// c = x1^2 + y1^2 - R^2;
// d = b*b - 4*a*c;
