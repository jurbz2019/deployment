# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

USE assessment;
SHOW events;
ALTER EVENT assessment.scheduler ENABLE; # enables scheduled runs
ALTER EVENT assessment.process_execution_records ENABLE; # enables A-Runs
