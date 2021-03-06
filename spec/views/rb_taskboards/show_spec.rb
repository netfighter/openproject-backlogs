#-- copyright
# OpenProject Backlogs Plugin
#
# Copyright (C)2013-2014 the OpenProject Foundation (OPF)
# Copyright (C)2011 Stephan Eckardt, Tim Felgentreff, Marnen Laibow-Koser, Sandro Munda
# Copyright (C)2010-2011 friflaj
# Copyright (C)2010 Maxime Guilbot, Andrew Vit, Joakim Kolsjö, ibussieres, Daniel Passos, Jason Vasquez, jpic, Emiliano Heyns
# Copyright (C)2009-2010 Mark Maglana
# Copyright (C)2009 Joe Heck, Nate Lowrie
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License version 3.
#
# OpenProject Backlogs is a derivative work based on ChiliProject Backlogs.
# The copyright follows:
# Copyright (C) 2010-2011 - Emiliano Heyns, Mark Maglana, friflaj
# Copyright (C) 2011 - Jens Ulferts, Gregor Schmidt - Finn GmbH - Berlin, Germany
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

require File.dirname(__FILE__) + '/../../spec_helper'

describe 'rb_taskboards/show' do
  let(:user1) { FactoryGirl.create(:user) }
  let(:user2) { FactoryGirl.create(:user) }
  let(:role_allowed) { FactoryGirl.create(:role,
    :permissions => [:create_impediments, :create_tasks, :update_impediments, :update_tasks])
  }
  let(:role_forbidden) { FactoryGirl.create(:role) }
  # We need to create these as some view helpers access the database
  let(:statuses) { [FactoryGirl.create(:status),
                    FactoryGirl.create(:status),
                    FactoryGirl.create(:status)] }

  let(:type_task) { FactoryGirl.create(:type_task) }
  let(:type_feature) { FactoryGirl.create(:type_feature) }
  let(:issue_priority) { FactoryGirl.create(:priority) }
  let(:project) do
    project = FactoryGirl.create(:project, :types => [type_feature, type_task])
    project.members = [FactoryGirl.create(:member, :principal => user1,:project => project,:roles => [role_allowed]),
                       FactoryGirl.create(:member, :principal => user2,:project => project,:roles => [role_forbidden])]
    project
  end

  let(:story_a) { FactoryGirl.create(:story, :status => statuses[0],
                                             :project => project,
                                             :type => type_feature,
                                             :fixed_version => sprint,
                                             :priority => issue_priority
                                             )}
  let(:story_b) { FactoryGirl.create(:story, :status => statuses[1],
                                             :project => project,
                                             :type => type_feature,
                                             :fixed_version => sprint,
                                             :priority => issue_priority
                                             )}
  let(:story_c) { FactoryGirl.create(:story, :status => statuses[2],
                                             :project => project,
                                             :type => type_feature,
                                             :fixed_version => sprint,
                                             :priority => issue_priority
                                             )}
  let(:stories) { [story_a, story_b, story_c] }
  let(:sprint)   { FactoryGirl.create(:sprint, :project => project) }
  let(:task) do
    task = FactoryGirl.create(:task, :project => project, :status => statuses[0], :fixed_version => sprint, :type => type_task)
    # This is necessary as for some unknown reason passing the parent directly
    # leads to the task searching for the parent with 'root_id' is NULL, which
    # is not the case as the story has its own id as root_id
    task.parent_id = story_a.id
    task
  end
  let(:impediment) { FactoryGirl.create(:impediment, :project => project, :status => statuses[0], :fixed_version => sprint, :blocks_ids => task.id.to_s, :type => type_task) }

  before :each do
    Setting.stub(:plugin_openproject_backlogs).and_return({"story_types" => [type_feature.id], "task_type" => type_task.id})
    view.extend RbCommonHelper
    view.extend TaskboardsHelper

    assign(:project, project)
    assign(:sprint, sprint)
    assign(:statuses, statuses)

    # We directly force the creation of stories by calling the method
    stories
  end

  describe 'story blocks' do

    it 'contains the story id' do
      render

      stories.each do |story|
        rendered.should have_selector "#story_#{story.id}" do
          with_selector ".id", Regexp.new(story.id.to_s)
        end
      end
    end

    it 'has a title containing the story subject' do
      render

      stories.each do |story|
        rendered.should have_selector "#story_#{story.id}" do
          with_selector ".subject", story.subject
        end
      end
    end

    it 'contains the story status' do
      render

      stories.each do |story|
        rendered.should have_selector "#story_#{story.id}" do
          with_selector ".status", story.status.name
        end
      end
    end

    it 'contains the user it is assigned to' do
      render

      stories.each do |story|
        rendered.should have_selector "#story_#{story.id}" do
          with_selector ".assigned_to_id", assignee.name
        end
      end
    end
  end

  describe 'create buttons' do

    it 'renders clickable + buttons for all stories with the right permissions' do
      User.stub(:current).and_return(user1)

      render

      stories.each do |story|
        assert_select "tr.story_#{story.id} td.add_new" do |td|
          td.count.should eq 1
          td.first.should have_content '+'
          td.first.should have_css '.clickable'
        end
      end
    end

    it 'does not render a clickable + buttons for all stories without the right permissions' do
      User.stub(:current).and_return(user2)

      render

      stories.each do |story|
        assert_select "tr.story_#{story.id} td.add_new" do |td|
          td.count.should eq 1
          td.first.should_not have_content '+'
          td.first.should_not have_css '.clickable'
        end
      end
    end

    it 'renders clickable + buttons for impediments with the right permissions' do
      User.stub(:current).and_return(user1)

      render

      stories.each do |story|
        assert_select '#impediments td.add_new' do |td|
          td.count.should eq 1
          td.first.should have_content '+'
          td.first.should have_css '.clickable'
        end
      end
    end

    it 'does not render a clickable + buttons for impediments without the right permissions' do
      User.stub(:current).and_return(user2)

      render

      stories.each do |story|
        assert_select '#impediments td.add_new' do |td|
          td.count.should eq 1
          td.first.should_not have_content '+'
          td.first.should_not have_css '.clickable'
        end
      end
    end

  end

  describe 'update tasks or impediments' do

    it 'allows edit and drag for all tasks with the right permissions' do
      User.stub(:current).and_return(user1)
      task
      impediment
      render

      assert_select ".model.work_package.task" do |task|
        task.count.should eq 1
        task.first.should_not have_css '.task.prevent_edit'
      end
    end

    it 'does not allow to edit and drag for all tasks without the right permissions' do
      User.stub(:current).and_return(user2)
      task
      impediment

      render

      assert_select ".model.work_package.task" do |task|
        task.count.should eq 1
        task.first.should have_css '.task.prevent_edit'
      end
    end

    it 'allows edit and drag for all impediments with the right permissions' do
      User.stub(:current).and_return(user1)
      task
      impediment

      render

      assert_select ".model.work_package.impediment" do |impediment|
        impediment.count.should eq 3 # 2 additional for the task and the invisible form
        impediment.first.should_not have_css '.impediment.prevent_edit'
      end
    end

    it 'does not allow to edit and drag for all impediments without the right permissions' do
      User.stub(:current).and_return(user2)
      task
      impediment

      render

      assert_select ".model.work_package.impediment" do |impediment|
        impediment.count.should eq 3 # 2 additional for the task and the invisible form
        impediment.first.should have_css '.impediment.prevent_edit'
      end
    end
  end
end
