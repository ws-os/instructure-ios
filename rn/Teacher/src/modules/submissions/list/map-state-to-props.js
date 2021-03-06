//
// Copyright (C) 2016-present Instructure, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

// @flow

import type {
  SubmissionListDataProps,
} from './submission-prop-types'
import { getSubmissionsProps } from './get-submissions-props'
import shuffle from 'knuth-shuffle-seeded'
import {
  getGroupSubmissionProps,
} from '../../groups/submissions/get-group-submission-props'

type RoutingProps = {
  courseID: string,
  assignmentID: string,
}

export function mapStateToProps ({ entities }: AppState, { courseID, assignmentID }: RoutingProps): SubmissionListDataProps {
  // submissions
  const assignmentContent = entities.assignments[assignmentID]
  const courseContent = entities.courses[courseID]
  let pointsPossible
  let groupAssignment = null
  if (assignmentContent && assignmentContent.data) {
    const a = assignmentContent.data
    const groupExists = a.group_category_id && courseContent.groups.refs
      .filter(ref => entities.groups[ref].group.group_category_id === a.group_category_id)
      .length > 0
    if (groupExists) {
      groupAssignment = {
        groupCategoryID: a.group_category_id,
        gradeIndividually: a.grade_group_students_individually,
      }
    }
    pointsPossible = assignmentContent.data.points_possible
  }

  let submissions
  if (groupAssignment && !groupAssignment.gradeIndividually) {
    submissions = getGroupSubmissionProps(entities, courseID, assignmentID)
  } else {
    submissions = getSubmissionsProps(entities, courseID, assignmentID)
  }

  let courseColor = '#FFFFFF'
  if (courseContent && courseContent.color) {
    courseColor = courseContent.color
  }

  let courseName = ''
  if (courseContent && courseContent.course) {
    courseName = courseContent.course.name
  }

  let anonymous = !!assignmentContent && assignmentContent.anonymousGradingOn ||
                  courseContent && courseContent.enabledFeatures.includes('anonymous_grading')
  let muted = !!assignmentContent && assignmentContent.data.muted

  let assignmentName = ''
  let gradingType = 'points'
  if (assignmentContent && assignmentContent.data) {
    assignmentName = assignmentContent.data.name
    gradingType = assignmentContent.data.grading_type
  }

  const sections = Object.values(entities.sections).filter((s) => {
    return s.course_id === courseID
  })

  return {
    groupAssignment,
    courseColor,
    courseName,
    pointsPossible,
    pending: submissions.pending,
    submissions: anonymous ? shuffle(submissions.submissions.slice(), assignmentID) : submissions.submissions,
    anonymous,
    muted,
    assignmentName,
    gradingType,
    sections,
  }
}
