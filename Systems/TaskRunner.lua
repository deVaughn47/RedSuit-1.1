local TaskRunner = {}
loadfile('Package')('TaskRunner', TaskRunner)

local jobs = {}

-- Utility function to safely access systems.TaskRunner
local function getTaskRunner()
    if systems and systems.TaskRunner then
        return systems.TaskRunner
    else
        -- Log an error if systems.TaskRunner is not initialized
        if TaskRunner.logger and TaskRunner.logger.log then
            TaskRunner.logger.log("[RedSuit] Error: 'systems.TaskRunner' is nil.")
        else
            print("[RedSuit] Error: 'systems.TaskRunner' is nil.")
        end
        return nil
    end
end

function TaskRunner.RunJob(callbackFn, delay, checkDilation, forceInPause, shouldLoop)
    checkDilation = checkDilation or false
    forceInPause = forceInPause or true
    shouldLoop = shouldLoop or false

    local taskRunner = getTaskRunner()
    if not taskRunner then
        -- Cannot proceed without TaskRunner
        return nil
    end

    return taskRunner:RunJob(_P.ScriptFunc.New(callbackFn), delay, checkDilation, forceInPause, shouldLoop)
end

function TaskRunner.ScheduleJob(callbackFn, interval, checkDilation, forceInPause)
    checkDilation = checkDilation or false
    forceInPause = forceInPause or true

    local taskRunner = getTaskRunner()
    if not taskRunner then
        -- Cannot proceed without TaskRunner
        return nil
    end

    return taskRunner:ScheduleJob(_P.ScriptFunc.New(callbackFn), interval, checkDilation, forceInPause)
end

function TaskRunner.OnInit()
    local taskRunner = getTaskRunner()
    if not taskRunner then
        -- Cannot proceed with initialization without TaskRunner
        return
    end

    Override('RedSuitLib.TaskRunner', 'RunJob;ScriptFuncInt32BoolBoolBool',
        function(this, callbackFn, delay, checkDilation, forceInPause, shouldLoop)
            local id = callbackFn.id

            if not _P.Callback.IsValid(id) then
                id = _P.Callback.GetId(_P.ScriptFunc.WrapOf(callbackFn))
            end

            local remainingTime = math.max(50, delay)
            local job = RedSuitLib_ScheduledCallback.New(id, remainingTime, checkDilation, forceInPause, shouldLoop)
            local delayId = Game.GetDelaySystem():DelayCallback(
                job,
                Game.GetTimeSystem():MillisecondsToSeconds(remainingTime),
                checkDilation
            )

            job.delayId = delayId
            jobs[id] = job

            return id
        end)

    Override('RedSuitLib.TaskRunner', 'GetRemainingTime',
        function(this, id)
            local job = jobs[id]

            if job == nil then
                return -1
            end

            if job.isHandledByTimer or not Game.GetDelaySystem():IsValid(job.delayId) then
                return job.remainingTime
            else
                return Game.GetTimeSystem():SecondsToMilliseconds(Game.GetDelaySystem():GetRemainingDelayTime(job.delayId))
            end

            return -1
        end)

    Override('RedSuitLib.TaskRunner', 'HasJob',
        function(this, id)
            local job = jobs[id]

            if job == nil then
                return false
            end

            return true
        end)

    Override('RedSuitLib.TaskRunner', 'CancelJob',
        function(this, id)
            local job = jobs[id]

            if job == nil then
                return false
            end

            if not job.isHandledByTimer then
                Game.GetDelaySystem():CancelCallback(job.delayId)
            end

            job:Destroy()

            return true
        end)

    Override('RedSuitLib.ScheduledCallback', 'Call', function(this)
        if not _P.Callback.IsValid(this.id) then
            return
        end

        local fn = _P.Callback.GetFn(this.id)

        if fn == nil then
            return
        end

        fn()

        if this.shouldLoop and _P.Callback.IsValid(this.id) then
            local taskRunner = getTaskRunner()
            if taskRunner then
                taskRunner:RunJob(
                    _P.Callback.GetRef(this.id),
                    this.initialDuration,
                    this.checkDilation,
                    this.forceInPause,
                    this.shouldLoop
                )
            else
                radioMod.logger.log("[RedSuit] Error: Cannot loop job as 'systems.TaskRunner' is nil.")
            end
        else
            this:Destroy()
        end
    end)

    Override('RedSuitLib.ScheduledCallback', 'Destroy', function(this)
        if jobs[this.id] == nil then
            return false
        end

        local ref = _P.Callback.GetRef(this.id)

        if ref ~= nil then
            ref:Destroy()
        end

        jobs[this.id] = nil

        return true
    end)

    Override('DelaySystem', 'IsValid', function(this, delayId)
        return this:GetRemainingDelayTime(delayId) ~= -1
    end)
end

function TaskRunner.OnUpdate(delta)
    local taskRunner = getTaskRunner()
    if not taskRunner then
        -- Cannot proceed without TaskRunner
        return
    end

    if not Game.GetSystemRequestsHandler():IsGamePaused() then
        if taskRunner.state ~= RedSuitLib_TaskRunnerState.Clean then
            TaskRunner.ProcessWithGameEngine()
        end

        taskRunner.runTime = 0

        return
    end

    taskRunner.runTime = taskRunner.runTime + Game.GetTimeSystem():SecondsToMilliseconds(delta)

    if taskRunner.runTime > taskRunner.tickTime then
        TaskRunner.ProcessWithTimer()
        taskRunner.runTime = 0
    end
end

function TaskRunner.OnShutdown()
    for _, job in pairs(jobs) do
        if not job.isHandledByTimer then
            Game.GetDelaySystem():CancelCallback(job.delayId)
        end

        job:Destroy()
    end

    jobs = {}
end

function TaskRunner.ProcessWithGameEngine()
    local taskRunner = getTaskRunner()
    if not taskRunner then
        -- Cannot proceed without TaskRunner
        return
    end

    for _, job in pairs(jobs) do
        if job.isHandledByTimer then
            TaskRunner.AttachDelaySystem(job)
            job.isHandledByTimer = false
        end
    end

    taskRunner.state = RedSuitLib_TaskRunnerState.Clean
end

function TaskRunner.ProcessWithTimer()
    local taskRunner = getTaskRunner()
    if not taskRunner then
        -- Cannot proceed without TaskRunner
        return
    end

    for _, job in pairs(jobs) do
        if job.forceInPause then
            if not job.isHandledByTimer then
                TaskRunner.DetachDelaySystem(job)
                job.isHandledByTimer = true
            else
                job.remainingTime = job.remainingTime - taskRunner.runTime

                if job.remainingTime <= 0 then
                    job:Call()
                end
            end

            if taskRunner.state ~= RedSuitLib_TaskRunnerState.Dirty then
                taskRunner.state = RedSuitLib_TaskRunnerState.Dirty
            end
        end
    end
end

function TaskRunner.AttachDelaySystem(job)
    local taskRunner = getTaskRunner()
    if not taskRunner then
        -- Cannot proceed without TaskRunner
        return
    end

    job.remainingTime = math.max(50, job.remainingTime - taskRunner.runTime)
    job.delayId = Game.GetDelaySystem():DelayCallback(
        job,
        Game.GetTimeSystem():MillisecondsToSeconds(job.remainingTime),
        job.checkDilation
    )
end

function TaskRunner.DetachDelaySystem(job)
    local taskRunner = getTaskRunner()
    if not taskRunner then
        -- Cannot proceed without TaskRunner
        return
    end

    job.remainingTime = taskRunner:GetRemainingTime(job.id)
    Game.GetDelaySystem():CancelCallback(job.delayId)
    job.delayId = nil
end

return TaskRunner
