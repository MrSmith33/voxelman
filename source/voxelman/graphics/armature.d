module voxelman.graphics.armature;

import voxelman.graphics.batch;
import voxelman.container.buffer;
import voxelman.math;

import dlib.math.transformation : fromEuler;

struct Armature
{
	struct Bone
	{
		Bone* parent;
		string name;
		Batch mesh;
		Matrix4f baseTransform = Matrix4f.identity;
		Matrix4f movement = Matrix4f.identity;
		Buffer!Bone children;

		Matrix4f transform() @property
		{
			return baseTransform * movement;
		}

		void reset()
		{
			movement = Matrix4f.identity;
		}

		void rotate(vec3 euler)
		{
			movement *= fromEuler(euler);
		}
	}

	string name;
	Bone root;
	/// Buffer which has reserved as many items as bones exist in this armature, can be used for recursive iteration.
	Buffer!Bone fullBuffer;

	this(string name, Matrix4f transform)
	{
		this.name = name;
		root.name = name ~ "_root";
		root.baseTransform = transform;
		root.reset();
		fullBuffer.reserve(1);
	}

	Bone* findBoneByName(string bone)
	{
		string fullName = this.name ~ '_' ~ bone;
		foreach (ref bone; this)
			if (bone.name == fullName)
				return &bone;
		return null;
	}

	void addRoot(string childName, Batch mesh, Matrix4f transform)
	{
		addChild(&root, childName, mesh, transform);
	}

	void addChild(string bone, string childName, Batch mesh, Matrix4f transform)
	{
		assert(findBoneByName(childName) == null, "Bone with name " ~ childName ~ " already exists");
		addChild(findBoneByName(bone), childName, mesh, transform);
	}

	void addChild(Bone* bone, string childName, Batch mesh, Matrix4f transform)
	{
		Bone newBone;
		newBone.name = this.name ~ '_' ~ childName;
		newBone.parent = bone;
		newBone.baseTransform = transform;
		newBone.mesh = mesh;
		newBone.reset();
		bone.children.put(newBone);
		fullBuffer.reserve(1);
		// don't return pointer to data because data might move on next allocation, use names instead
	}

	/// Iterates over each bone in the tree structure by ref
	int opApply(scope int delegate(ref Bone) dg)
	{
		auto todo = fullBuffer;
		todo.clear();
		auto result = dg(root);
		if (result)
			return result;
		todo.put(root);
		while (!todo.empty)
		{
			auto children = todo.back.children.data;
			todo.unput(1);
			foreach (ref bone; children)
			{
				result = dg(bone);
				if (result)
					return result;
				todo.put(bone);
			}
		}
		return result;
	}
}

///
unittest
{
	import voxelman.graphics.color : Colors;

	Batch head = Batch.cube(vec3(0.5f, 0.5f, 0.5f), Colors.white, true);
	Batch body_ = Batch.cube(vec3(0.5f, 0.8f, 0.5f), Colors.white, true);

	Armature armature = Armature("human", translationMatrix(vec3(0, 1.5f, 0)));
	armature.addRoot("body", body_, Matrix4f.identity);
	armature.addChild("body", "head", head, translationMatrix(vec3(0, 0.65f, 0)));

	// after adding all bones

	auto bodyBone = armature.findBoneByName("body");
	auto headBone = armature.findBoneByName("head");
	// bones should not be modified at this point as they might mess up bone references

	bodyBone.rotate(vec3(degtorad(90.0f), 0, 0));
	headBone.rotate(vec3(0, degtorad(90.0f), 0));

	// should be bent down, looking left now
}
