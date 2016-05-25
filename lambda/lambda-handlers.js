require('coffee-script/register')
iamUtils = require('./iam-utils')

exports.checkAccessKeyRotationHandler = iamUtils.checkAccessKeyRotation
exports.checkMFAEnabled = iamUtils.checkMFAEnabled
