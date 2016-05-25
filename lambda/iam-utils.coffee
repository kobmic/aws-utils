AWS = require "aws-sdk"
async = require "async"
iam = new AWS.IAM()
sns = new AWS.SNS()

# access key rotation interval in days
ROTATION_INTERVAL_IN_DAYS = 6

# sns topic for alarms
# TODO: replace with your topic arn
ALARM_TOPIC_ARN = undefined

# calculate start date of rotation interval
calcDaysAgo = (numberOfDays) =>
    now = new Date()
    ago = now.getDate() - numberOfDays
    new Date().setDate(ago)

# check if access key needs rotation
filterUnrotatedKeys = (accessKeyData) =>
    isActive = (key) => key.Status == 'Active'
    needsRotation = (key) => startRotationIntervall > key.CreateDate
    activeKeys = accessKeyData.AccessKeyMetadata.filter(isActive)
    startRotationIntervall = calcDaysAgo(ROTATION_INTERVAL_IN_DAYS)
    activeKeys.filter(needsRotation)

# publish warming message to configured SNS topic
publishUnrotatedKeysAlarm = (keys, callback) =>
    params = {
        Message: JSON.stringify(keys),
        Subject: "Warning: One ore more access keys in IAM need rotation.",
        TopicArn: ALARM_TOPIC_ARN
    }
    sns.publish(params, callback)

# publish warming message to configured SNS topic
publishNoMFADeviceAlarm = (users, callback) =>
    params = {
        Message: JSON.stringify(users),
        Subject: "Warning: One ore more users do not have their MFA Device enabled.",
        TopicArn: ALARM_TOPIC_ARN
    }
    if (ALARM_TOPIC_ARN)
        sns.publish(params, callback)

# list IAM users
# callback(err, userNames)
listIamUsers = (callback) =>
    iam.listUsers {}, (err, data) =>
        if (err)
            console.log(err, err.stack)
            callback(err)
        else
            userNames = data.Users.map (user) => user.UserName
        callback(null, userNames)

# list access keys for user and filter to only keys that need rotation
listAccessKeys = (name, callback) =>
    iam.listAccessKeys {UserName: name}, (err, data) =>
        if (err)
            console.log(err)
            return callback(err)
        unrotated = filterUnrotatedKeys(data)
        callback(null, unrotated)

# get Login profile for user, all users that have a login profile
# need MFA enabled
getLoginProfile = (name, callback) =>
    iam.getLoginProfile {UserName: name}, (err, data) =>
        if (err)
            if (err.code != "NoSuchEntity")
                console.log(err)
                return callback(err)
        callback(null, data)

# list MFA device for user
listMFADevice = (name, callback) =>
    iam.listMFADevices {UserName: name}, (err, data) =>
        if (err)
            console.log(err)
            return callback(err)
        if (data.MFADevices[0])
            data.MFADevices[0].CheckedUserName = name
        else
            data.MFADevices.push({CheckedUserName : name})
        callback(null, data.MFADevices)

# Lambda handler
# check if there are any access keys that need to be rotated
exports.checkAccessKeyRotation = (event, context, callback)  =>
    console.log("checkAccessKeyRotation")
    listIamUsers (err, userNames) =>
        if (err)
    	    console.log(err)
	        callback(err)
        else
            unrotatedKeys = []
            async.map userNames, listAccessKeys, (err, results) ->
                if (err)
                    console.log(err)
                    callback(err)
                else
                    flattened = [].concat.apply([], results)
                    if (flattened.length > 0)
                        publishUnrotatedKeysAlarm(flattened, callback)
                    else
                        callback()

# Lambda handler
exports.checkMFAEnabled = (event, context, callback)  =>
    console.log("checkMFAEnabled")
    listIamUsers (err, userNames) =>
        if (err)
            console.log(err)
            callback(err)
        else
            async.map userNames, getLoginProfile, (err, loginProfiles) ->
                usersWithProfiles= (loginProfiles.filter (profile) => profile != null).map (profile) => profile.LoginProfile.UserName
                async.map usersWithProfiles, listMFADevice, (err, userMFADevices) ->
                    if (err)
                        console.log(err)
                        callback(err)
                    flattened = [].concat.apply([], userMFADevices)
                    disabledDevices = flattened.filter (device) -> !device.SerialNumber

                    if (disabledDevices.length > 0)
                        publishNoMFADeviceAlarm(disabledDevices, callback)
                    else
                        callback()
                    callback(err)

exports.checkMFAEnabled null, null, (err, result) ->
    console.log "done"
