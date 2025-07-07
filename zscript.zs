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
			HDBulletTracker tracker = _BulletTracker[i];
			if (tracker.Bullet != bullet)
				continue;

			// make the bullet visible if it had a really short life AND travelled past a certain distance
			double deltaLength = (tracker.Model.DelayTimer > 0)? Level.Vec3Diff(tracker.Model.Pos, bullet.Pos).Length() : 0;
			if (deltaLength > 20)
			{
				Vector3 tracerEndPos = bullet.Pos;

				// if the bullet ricochets, don't interpolate with the bullet's position (because it looks wrong)
				let tracer = HDBulletModelTracer.CreateAndTrace(tracker.Model);
				bool hasRicochet = (tracer.HasHitGeometry && !(
					(bullet.Pos.X <= tracer.Results.HitPos.X + 2 && bullet.Pos.X >= tracer.Results.HitPos.X - 2)
					&& (bullet.Pos.Y <= tracer.Results.HitPos.Y + 2 && bullet.Pos.Y >= tracer.Results.HitPos.Y - 2)
					&& (bullet.Pos.Z <= tracer.Results.HitPos.Z + 2 && bullet.Pos.Z >= tracer.Results.HitPos.Z - 2)
				));
				if (hasRicochet)
					tracerEndPos = tracer.Results.HitPos;

				// Console.PrintF("rico? "..(hasRicochet).." "..tracer.Results.HitPos.." "..bullet.Pos.." len:"..Level.Vec3Diff(tracker.Model.Pos, tracer.Results.HitPos).Length());
				tracker.Model.Alpha = (deltaLength > 25)? 1.0 : 0.5;
				tracker.Model.UpdateAnglePitch(tracker.Model.Pos, tracerEndPos);
				tracker.Model.UpdatePos(tracker.Model.Pos, tracerEndPos);
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

class HDBulletModelTracer : LineTracer
{
	bool HasHitGeometry;

	static HDBulletModelTracer CreateAndTrace(HDBulletModel model)
	{
		let t = HDBulletModelTracer(new("HDBulletModelTracer"));
		// Console.PrintF(model.Pos.." len:"..model.PrevVel.Length() * (model.DelayTimer + 1));
		t.Trace(
			model.Pos,
			model.CurSector,
			model.PrevVel,
			// model.PrevVel.Unit(),
			model.PrevVel.Length() * (model.DelayTimer + 1),
			TRACE_HitSky,
			ignoreAllActors: true
		);

		return t;
	}

	override ETraceStatus TraceCallback()
	{
		if (
			results.HitType == TRACE_HitFloor
			|| results.HitType == TRACE_HitCeiling
			|| (
				results.HitType == TRACE_HitWall
				&& (
					results.Tier != TIER_Middle
					|| (
						results.HitLine
						&& results.HitLine.flags & (Line.ML_BLOCKHITSCAN | Line.ML_BLOCKPROJECTILE)
					)
				)
			)
		)
		{
			// Console.PrintF("wall yes");
			// Console.PrintF(""..results.Distance.." "..results.SrcFromTarget);
			HasHitGeometry = true;
			return TRACE_Stop;
		}

		return TRACE_Skip;
	}
}

// i only used this for "tracing" the bullet's path, ignore
class HDDebugBulletModel : Actor
{
	Default
	{
		+NOGRAVITY;
		Translation "AllRed";
	}

	States
	{
		Spawn:
			BLET A -1;
			wait;
	}
}

// no visualthinker because it don't support models :[
class HDBulletModel : Actor
{
	int DelayTimer;
	int ToDestroy;
	Vector3 PrevVel;

	Default
	{
		RenderStyle "Translucent";
		+BRIGHT;
		+NOBLOCKMAP;
		+NOINTERACTION;
		FloatBobPhase 0;
		+SYNCHRONIZED;
	}

	static HDBulletModel Create(HDBulletActor target)
	{
		let t = HDBulletModel(Actor.Spawn(
			"HDBulletModel",
			target.pos
		));
		t.Target = target;
		t.Scale = (0.10, 0.10); // fixed size because shotgun tracers are HUGE if i use scale
		t.PrevVel = target.Vel; // in case the bullet ricochets

		return t;
	}

	override void BeginPlay()
	{
		ToDestroy = false;
		Alpha = 0.0;
		DelayTimer = Random[HDBulletModel](1, 2);
		// Alpha = 1.0;
		// DelayTimer = 0;
	}

	void UpdateAnglePitch(Vector3 prev, Vector3 next)
	{
		Vector3 delta = Level.Vec3Diff(prev, next);
		Angle = VectorAngle(delta.X, delta.Y);

		// the following code is taken from https://github.com/swampyrad/HDBulletTracers/blob/main/zscript.txt
		// Use atan in conjunction with the inverse of vel.z (then add 180).
		// Condensed by phantombeta (spectralalpha on the HD Discord)
		Pitch = atan2(-(delta.Z), delta.XY.Length()) + 180;
	}

	void UpdatePos(Vector3 prev, Vector3 next)
	{
		Vector3 inbetweenLength = Level.Vec3Diff(prev, next) * FRandom[HDBulletModel](0.4, 0.6);
		SetOrigin(Level.Vec3Offset(prev, inbetweenLength), true);
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

		PrevVel = Target.Vel;
		UpdateAnglePitch(Target.Prev, Target.Pos);
		UpdatePos(Target.Prev, Target.Pos);

		// this is just to prevent the tracer from appearing in your face
		if (DelayTimer > 0)
		{
			--DelayTimer;
			return;
		}

		Alpha = 1.0;
	}

	States
	{
		Spawn:
			BLET A -1;
			wait;
	}
}
