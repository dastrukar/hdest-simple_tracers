version "4.14"

class BulletModelHandler : StaticEventHandler
{
	private Array<HDBulletTracker> _BulletTracker;

	override void WorldThingSpawned(WorldEvent e)
	{
		let bullet = HDBulletActor(e.Thing);
		if (!bullet)
			return;

		let model = HDBulletModel.Create(bullet);
		let tracker = HDBulletTracker.Create(bullet, model);
		_BulletTracker.Push(tracker);
	}

	override void WorldThingDestroyed(WorldEvent e)
	{
		let bullet = HDBulletActor(e.Thing);
		if (!bullet)
			return;

		for (int i = 0; i < _BulletTracker.Size(); i++)
		{
			let tracker = _BulletTracker[i];
			if (tracker.Bullet != bullet)
				continue;

			// make the bullet visible if it had a really short life
			if (tracker.Model.DelayTimer > 0)
			{
				tracker.Model.Alpha = 1.0;
				tracker.Model.UpdatePos(tracker.Model.Pos, bullet.Pos);
			}

			tracker.Destroy();
			_BulletTracker.Delete(i);
			--i;
		}
	}
}

// we track the bullet here, because it doesn't get invalidated immediately when destroyed, for some reason
class HDBulletTracker
{
	HDBulletActor Bullet;
	HDBulletModel Model;

	static HDBulletTracker Create(HDBulletActor bullet, HDBulletModel model)
	{
		let t = HDBulletTracker(new("HDBulletTracker"));
		t.bullet = bullet;
		t.model = model;

		return t;
	}
}

// no visualthinker because it don't support models :[
class HDBulletModel : Actor
{
	int DelayTimer;
	Vector3 PosOffset;
	int ToDestroy;

	Default
	{
		RenderStyle "Translucent";
	}

	static HDBulletModel Create(HDBulletActor target)
	{
		let t = HDBulletModel(Actor.Spawn(
			"HDBulletModel",
			target.pos
		));
		t.Target = target;
		t.Scale = (0.10, 0.10); // fixed size because shotgun tracers are HUGE if i use scale
		t.UpdateAnglePitch();

		return t;
	}

	override void BeginPlay()
	{
		ToDestroy = false;
		Alpha = 0.0;
		DelayTimer = Random[HDBulletModel](1, 2);
		// Alpha = 1.0;
		// DelayTimer = 0;
		PosOffset = (0, 0, 0);
	}

	// the following code is taken from https://github.com/swampyrad/HDBulletTracers/blob/main/zscript.txt
	void UpdateAnglePitch()
	{
		// Math taken from https://stackoverflow.com/questions/2782647/how-to-get-yaw-pitch-and-roll-from-a-3d-vector
		// Pitch: ToolmakerStever
		// used for bullet types that have no set angle (should be identical to bullet angle anyway).
		Angle = atan2(Target.Vel.Y, Target.Vel.X);
		
		// Use atan in conjunction with the inverse of vel.z (then add 180).
		// Condensed by phantombeta (spectralalpha on the HD Discord)
		Pitch = atan2(-(Target.Vel.Z),Target.Vel.XY.Length()) + 180;
	}

	void UpdatePos(Vector3 prev, Vector3 next)
	{
		Vector3 inbetweenLength = Level.Vec3Diff(prev, next) * FRandom[HDBulletModel](0.4, 0.6);
		SetOrigin(Level.Vec3Offset(prev, inbetweenLength + PosOffset), true);
	}

	override void Tick()
	{
		if (!self || bDestroyed || IsFrozen())
			return;

		// bullet gone, you have no purpose anymore
		if (!Target)
		{
			// delay destruction just to show off for a bit :]
			if (!ToDestroy)
			{
				ToDestroy = true;
				return;
			}

			Destroy();
			return;
		}

		// this is just to prevent the tracer from appearing in your face
		if (DelayTimer > 0)
		{
			--DelayTimer;
			return;
		}

		Alpha = 1.0;
		UpdateAnglePitch();
		UpdatePos(Target.Prev, Target.Pos);
	}

	States
	{
		Spawn:
			BLET A -1;
			wait;
	}
}
