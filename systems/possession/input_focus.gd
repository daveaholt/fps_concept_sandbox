class_name InputFocus
extends RefCounted


static func may_act(sampler) -> bool:
	if sampler == null or not is_instance_valid(sampler):
		return true
	if not sampler.has_method("window_focused"):
		return true
	return sampler.window_focused()
