package vis

import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"
import "core:time"
import "core:slice"


request_new_scroll :: proc(using editor: ^CodeEditor, new_scroll_offset: [2]i32) {
	current_time := time.to_unix_nanoseconds(time.now())/1e6

	using smooth_scroll

	already_scrolling := current_time<=latest_time+auto_cast duration

	// determine new duration
	new_duration : type_of(duration)
	{
		// interval_ratio :: 200 // default for firefox general.smoothScroll.durationToIntervalRatio
		interval_ratio :: 50
		min_duration :: 100
		max_duration :: 150

		if !already_scrolling { // not scrolling
			new_duration = max_duration
			max_delta := u16(max_duration/interval_ratio)
			prev_event_dts[0] = max_delta
			prev_event_dts[1] = max_delta
		} else { // currently scrolling
			latest_delta := u16(current_time-latest_time)
			average_delta := (prev_event_dts[0]+prev_event_dts[1]+latest_delta)/3
			prev_event_dts[0] = prev_event_dts[1]
			prev_event_dts[1] = latest_delta

			new_duration = clamp(average_delta*interval_ratio, min_duration, max_duration)
		}
	}

	velocity: [2]i32 // pixels per second
	{
		progress := f32(current_time-latest_time)/auto_cast duration
		if progress >= 1 {
			velocity = {0, 0}
		} else {
			p2 := scroll_control_point2
			p1s := control_point1s
			x_t := get_bezier_t_for_x(progress, p1s.x.x, p2.x)
			y_t := get_bezier_t_for_x(progress, p1s.y.x, p2.x)
			x_grad := calc_bezier_grad(x_t, p1s.x, p2)
			y_grad := calc_bezier_grad(y_t, p1s.y, p2)
			get_velocity :: #force_inline proc(grad: [2]f32, multiplier: f32) -> i32 {
				dt := grad.x
				dr := grad.y
				if dt==0 {
					return dr>=0 ? max(i32) : min(i32)
				}
				// pixels/ms -> pixels/s
				return i32(math.round(dr/dt * multiplier * 1000))
			}
			velocity.x = get_velocity(x_grad, f32(scroll_offset.x - start_pos.x)/f32(duration))
			velocity.y = get_velocity(y_grad, f32(scroll_offset.y - start_pos.y)/f32(duration))
		}
	}

	get_control_point1 :: #force_inline proc(total_distance: i32, #any_int duration: int, velocity: i32) -> (p1: [2]f32) {
		// Ensure that initial velocity equals the current velocity for smooth experience:
		// initial velocity = initialrve (normalised), grad0  *  scaling factor
		// maxe the initial gradient:
		if total_distance==0 {return {0,0}}
		grad0 := (f32(velocity)/1000) * (f32(duration) / f32(total_distance))
		
		// First control point p1 is (dt, dr) where dt and dr are normalised time and distance
		// Thus the initial gradient grad0 = dr/dt
		// For scroll_velocity_coeff to represent the distance |p1-p0| independent of current velocity,
		// dt and dr must be points on a circle
		p1.x = scroll_velocity_coeff / math.sqrt(1+grad0*grad0)
		p1.y = p1.x * grad0
		return 
	}

	// update the scroll destination
	scroll_offset = new_scroll_offset
	start_pos = contents_rect.coords.xy-view_rect.coords.xy
	latest_time = current_time
	duration = new_duration

	control_point1s.x = get_control_point1((scroll_offset.x-start_pos.x), duration, velocity.x)
	control_point1s.y = get_control_point1((scroll_offset.y-start_pos.y), duration, velocity.y)
}

// equivalent parameters to Firefox/Gecko's
scroll_velocity_coeff :: 0.15 // default is 0.25 for general.smoothScroll.currentVelocityWeighting
scroll_deceleration_coeff :: 0.4 // default is 0.4 for  general.smoothScroll.stopDecelerationWeighting

scroll_control_point2 :: [2]f32{1-scroll_deceleration_coeff, 1}

// also see keySplines https://www.w3.org/TR/smil-animation/
// and https://www.desmos.com/calculator/wex6j3vcwb
// start and end control points p0=(0,0) and p3=(1,1)
// cubic Bézier curve

// returns the point on the Bezier curve at t with control points p1, p2
// p1 and p2 are either (x,y) points or the x or y components
// ie returns x(t) when p1=x1, p2=x2
calc_bezier :: proc(t: f32, p1: $P, p2: P) -> P {
	// use Horner's method for optimal evaluation
	return t*((3*p1) + t*((3*p2-6*p1) + t*(1-3*p2+3*p1)))
}
calc_bezier_grad :: proc(t: f32, p1: $P, p2: P) -> P {
	return 3*p1 + t*((6*p2-12*p1) + t*(3-9*p2+9*p1))
}

// the curve is monotonically increasing from (0,0) to (1,1)
get_bezier_t_for_x :: proc(x: f32, p1: f32, p2: f32) -> f32 {
	if x==1 {return 1}

	t := x // initial guess

	grad := calc_bezier_grad(t, p1, p2)
	if grad >= 0.02 { // Newton-Raphson method
		n_its :: 5
		min_grad :: 0.02
		for i in 0..<n_its {
			err := calc_bezier(t, p1, p2)-x
			grad = calc_bezier_grad(t, p1, p2)
			if grad==0 {break}
			t -= err/grad
		}

	} else { // Binary search
		max_err :: 0.0000001
		max_its :: 10
		t1 : f32 = 0
		t2 : f32 = 1
		n_its := 1
		for {
			err := calc_bezier(t, p1, p2)-x
			if err>0 {
				t2 = t
			} else {
				t1 = t
			}
			if math.abs(err)<=max_err || n_its==max_its {
				break
			}
			t = (t1+t2)/2
			n_its += 1
		}
	}
	return t
}