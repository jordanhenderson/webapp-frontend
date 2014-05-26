-- core/process.lua
-- Main instance handling/request processing script.
@include 'plugins/constants.lua'

--The global (current) request object.
request = nil
--The lua request object.
r = nil

common = compile("common.lua")
local requests = compile("core/requests.lua")

--asynchronous event table. Used to enable concurrent 
local events = common.new_table(NUM_EVENTS, 0)

function start_request()
	requests()
	return 1
end

function run_coroutine(f)
	while f do 
		f = coroutine.yield(f()) 
	end
end

local ev = coroutine.create(run_coroutine)
--use event_ctr to 'round-robin' events, to speed up empty event finding
local event_ctr = 1

request = c.Request_GetNext(worker)
while request ~= nil do
	r = request.r
	local co = tonumber(r.co)
	if co > 0 then
		ev = events[co]
	end
	local ret
	
	_, ret = coroutine.resume(ev, start_request)

	--co may have changed, indicating a yield.
	if ret ~= 1 then
		--ret not 1, must have yielded before end of start_request.
		--Store the coroutine for later.
		--find an empty slot
		local target_ev = 0
		local num_events = #events
		--Simple (round robin) search algorithm. Search from event_ctr->end
		for i = event_ctr, num_events do
			if events[i] == nil then
				target_ev = i
				break
			end
		end
		
		if target_ev == 0 then
			--Search from 1->event_ctr.
			for i = 1, event_ctr do
				if events[i] == nil then
					target_ev = i
					break
				end
			end
		end
		
		--Still no free event found? Then just place at end of table.
		if target_ev == 0 then
			target_ev = num_events
		end
		
		events[target_ev] = ev
		--Provide a way for the request to resume the coroutine.
		r.co = target_ev
		--clear base event for next loop.
		ev = coroutine.create(run_coroutine)
		event_ctr = target_ev + 1
		--Reset event_ctr when it reaches the max value.
		if event_ctr > NUM_EVENTS then
			event_ctr = 1
		end
	else
		--event has finished. Ensure we clear out the old coroutine.
		if co > 0 then events[co] = nil end
		--Clean up the request
		c.Request_Finish(worker, request)
	end
	request = c.Request_GetNext(worker)
end
