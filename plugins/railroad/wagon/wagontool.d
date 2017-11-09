/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.wagon.wagontool;

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

	float wagonAxisDistance = 12;
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
		railPos = RailPos(worldInteraction.blockPos);
		data = railAt(railPos);
	}

	private RailData railAt(RailPos pos)
	{
		ushort targetEntityId = blockEntityManager.getId("rail");
		return getRailAt(pos, targetEntityId, clientWorld.worldAccess, clientWorld.entityAccess);
	}

	// Uses current railPos
	WagonPos[2] iteratePairs(RailSegment segment)
	{
		FaceSide[2] sides = segmentInfos[segment].sides;

		RailPos adjacentPos0 = railPos.posInDirection(sides[0]);
		RailData adjacentData0 = railAt(adjacentPos0);
		FaceSide connectedViaSide0 = oppFaceSides[sides[0]];

		RailPos adjacentPos1 = railPos.posInDirection(sides[1]);
		RailData adjacentData1 = railAt(adjacentPos1);
		FaceSide connectedViaSide1 = oppFaceSides[sides[1]];

		foreach(adjSegment0; adjacentData0.getSegments)
		if (segmentInfos[adjSegment0].sideConnections[connectedViaSide0])
		{
			RailPos adjacentPos0 = railPos.posInDirection(sides[0]);
			FaceSide connectedViaSide0 = oppFaceSides[sides[0]];

			foreach(adjSegment1; adjacentData1.getSegments)
			if (segmentInfos[adjSegment1].sideConnections[connectedViaSide1])
			{
				RailPos adjacentPos1 = railPos.posInDirection(sides[1]);
				FaceSide connectedViaSide1 = oppFaceSides[sides[1]];
				// here we have a pair of segments connected to main segment
				WagonPos[2] positions = createWagonPlacement(
					segment,
					adjSegment0, connectedViaSide0,
					adjSegment1, connectedViaSide1);
				return positions;
			}
		}
		return (WagonPos[2]).init;
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

	vec3 pointSize = vec3(0.5f,0.5f,0.5f);
	vec3 pointOffset = vec3(0.25f,0.25f,0.25f);

	WagonPos[2] createWagonPlacement(
		RailSegment segmentC,
		RailSegment segment0, FaceSide connectedViaSide0,
		RailSegment segment1, FaceSide connectedViaSide1)
	{
		if (segmentC == segment0 && segment0 == segment1 &&
			(segment0 == RailSegment.zneg || segment0 == RailSegment.xpos))
		{
			// if all are straight rails
			vec3 railWorldPos = vec3(railPos.toBlockWorldPos.xyz);

			FaceSide[2] sides = segmentInfos[segmentC].sides;
			vec3 pointA = railTileConnectionPoints[sides[0]];
			vec3 pointB = railTileConnectionPoints[sides[1]];
			vec3 pointC = vec3(worldInteraction.hitPosition);
			vec3 cursorOnCenterRail = project_point_to_line_segment(pointA, pointB, pointC-railWorldPos);

			vec3 railVector = pointB - pointA;
			railVector.normalize;
			vec3 wagonA = railWorldPos + vec3(0,1,0) + cursorOnCenterRail - railVector * wagonAxisDistance/2;
			vec3 wagonB = railWorldPos + vec3(0,1,0) + cursorOnCenterRail + railVector * wagonAxisDistance/2;

			//graphics.debugText.putfln("wagon %s");

			graphics.debugBatch.putLine(wagonA, wagonB, Colors.black);
			graphics.debugBatch.putCube(wagonA-pointOffset, pointSize, Colors.black, true);
			graphics.debugBatch.putCube(wagonB-pointOffset, pointSize, Colors.black, true);

			return (WagonPos[2]).init;
		}
		else
		{
			FaceSide[2] sides = segmentInfos[segmentC].sides;
			vec3 pointA = railTileConnectionPoints[sides[0]];
			vec3 pointB = railTileConnectionPoints[sides[1]];
			vec3 pointC = vec3(worldInteraction.hitPosition - railPos.toBlockWorldPos.xyz);
			vec3 cursorOnSegment = project_point_to_line_segment(pointA, pointB, pointC);

			//graphics.debugBatch.putCube(railWorldPos+cursorOnSegment-pointOffset, pointSize, Colors.red, true);


		}

		return (WagonPos[2]).init;
	}

	// Assumes non-empty rail
	void findWagonPlacement()
	{
		assert(!data.empty);

		vec3 railWorldPos = vec3(railPos.toBlockWorldPos.xyz);
		vec3 pointC = vec3(worldInteraction.hitPosition - railPos.toBlockWorldPos.xyz);

		vec3 vertOff = vec3(0,1,0);
		vec3 wagonVector = vec3(cos(wagonRotation), 0, sin(wagonRotation));
		vec3 wagonA = railWorldPos + vertOff + pointC - wagonVector * wagonAxisDistance/2;
		vec3 wagonB = railWorldPos + vertOff + pointC + wagonVector * wagonAxisDistance/2;
		vec3[2] wagonPoints = [wagonA-vertOff, wagonB-vertOff];
		graphics.debugText.putfln(" wagA %s wagB %s", wagonPoints[0], wagonPoints[1]);

		// Shadow wagon
		graphics.debugBatch.putLine(wagonA, wagonB, Color4ub(0,0,0,64));
		graphics.debugBatch.putCube(wagonA-pointOffset, pointSize, Color4ub(0,0,0,64), true);
		graphics.debugBatch.putCube(wagonB-pointOffset, pointSize, Color4ub(0,0,0,64), true);
		graphics.debugText.putfln("wagon rotation %.1f", radtodeg(wagonRotation));

		vec3[2] resultPos;// = railWorldPos + railTileConnectionPoints[sidesC[0]];
		RailPos[2] resultRail = [railPos, railPos];
		RailSegment[2] resultSegment;
		ubyte[2] resultOuterIndex;

		// errors say how far is calculated position to the given one
		float segmentError = float.infinity;
		//float[2] errors;

		// Find best central segment
		foreach(i, segment; data.getSegments)
		{
			FaceSide[2] sides = segmentInfos[segment].sides;
			// Set first approximation
			vec3 railA = railWorldPos + railTileConnectionPoints[sides[0]]-vec3(0f,0.5f,0f);
			vec3 railB = railWorldPos + railTileConnectionPoints[sides[1]]-vec3(0f,0.5f,0f);
			//graphics.debugText.putfln(" railA %s railB %s", railA, railB);

			float errorAA = distancesqr(railA, wagonPoints[0]);
			float errorAB = distancesqr(railA, wagonPoints[1]);
			float errorBB = distancesqr(railB, wagonPoints[1]);
			float errorBA = distancesqr(railB, wagonPoints[0]);

			float error0 = errorAA + errorBB;
			float error1 = errorAB + errorBA;

			float newError = min(error0, error1);

			//graphics.debugText.putfln(" AA %s AB %s BB %s BA %s", errorAA, errorAB, errorBB, errorBA);
			//graphics.debugText.putfln(" error of %s is %.1f", segment, newError);

			void setSegment(int idx0, int idx1)
			{
				resultPos[idx0] = railA;
				resultPos[idx1] = railB;
				//errors[idx0] = error0;
				//errors[idx1] = error1;
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

		// Best first segment
		graphics.debugBatch.putLine(vertOff + resultPos[0], vertOff + resultPos[1], Color4ub(0,255,0,255));
		graphics.debugBatch.putCube(vertOff + resultPos[0]-pointOffset, pointSize, Color4ub(255,0,0,255), true);
		graphics.debugBatch.putCube(vertOff + resultPos[1]-pointOffset, pointSize, Color4ub(0,255,0,255), true);
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

		if (!data.empty)
		{
			vec3 railWorldPos = vec3(railPos.toBlockWorldPos.xyz);

			findWagonPlacement();

			// Segments of hovered rail tile
			foreach(i, segment; data.getSegments)
			{
				enum layerDist = 0.25f;
				//drawRailsAt(railWorldPos + vec3(0, i*layerDist, 0), segment, colorsArray[i+2]);

				FaceSide[2] sides = segmentInfos[segment].sides;

				// try placing a wagon
				//WagonPos[2] positions = iteratePairs(segment);
				//renderer.debugBatch.putLine(positions[0].dimPosition, positions[1].dimPosition, Colors.black);

				//vec3 wagonPos0 = positions[0].dimPosition;
				//vec3 wagonPos1 = positions[1].dimPosition;

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
						//drawRailsAt(adjRailWorldPos + vec3(0, i*layerDist, 0), adjSegment, colorsArray[i+2]);
					}
				}
			}
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

// (1) x² + y² = R²
// (2) x = t(x₁-x₂) + x₂
// (3) y = t(y₁-y₂) + y₂
// We substitute (2) and (3) into (1) and get quadratic equation
// t²((x₁-x₂)² + (y₁-y₂)²) + t2((y₁-y₂)y₂ + (x₁-x₂)x₂) + x₂ + y₂ - R² = 0
// solve for t

// a = (x1 - x2)^2 + (y1 - y2)^2;
// b = 2 * ((y1-y2)*y2 + (x1-x2)*x2);
// c = x^2 + y^2 - R^2;
// d = b*b - 4*a*c;
