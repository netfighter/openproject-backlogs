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

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Story do
  let(:user) { @user ||= FactoryGirl.create(:user) }
  let(:role) { @role ||= FactoryGirl.create(:role) }
  let(:status1) { @status1 ||= FactoryGirl.create(:status, :name => "status 1", :is_default => true) }
  let(:type_feature) { @type_feature ||= FactoryGirl.create(:type_feature) }
  let(:version) { @version ||= FactoryGirl.create(:version, :project => project) }
  let(:version2) { FactoryGirl.create(:version, :project => project) }
  let(:sprint) { @sprint ||= FactoryGirl.create(:sprint, :project => project) }
  let(:issue_priority) { @issue_priority ||= FactoryGirl.create(:priority) }
  let(:task_type) { FactoryGirl.create(:type_task) }
  let(:task) { FactoryGirl.create(:story, :fixed_version => version,
                                      :project => project,
                                      :status => status1,
                                      :type => task_type,
                                      :priority => issue_priority) }
  let(:story1) { FactoryGirl.create(:story, :fixed_version => version,
                                        :project => project,
                                        :status => status1,
                                        :type => type_feature,
                                        :priority => issue_priority) }

  let(:story2) { FactoryGirl.create(:story, :fixed_version => version,
                                        :project => project,
                                        :status => status1,
                                        :type => type_feature,
                                        :priority => issue_priority) }

  let(:project) do
    unless @project
      @project = FactoryGirl.build(:project)
      @project.members = [FactoryGirl.build(:member, :principal => user,
                                                 :project => @project,
                                                 :roles => [role])]
    end
    @project
  end

  before(:each) do
    ActionController::Base.perform_caching = false

    Setting.stub(:plugin_openproject_backlogs).and_return({"points_burn_direction" => "down",
                                                            "wiki_template"         => "",
                                                            "card_spec"             => "Sattleford VM-5040",
                                                            "story_types"           => [type_feature.id.to_s],
                                                            "task_type"             => task_type.id.to_s })
    project.types << task_type
  end

  describe "Class methods" do
    describe :backlogs do

      describe "WITH one sprint
                WITH the sprint having 1 story" do
        before(:each) do
          story1
        end

        it { Story.backlogs(project, [version.id])[version.id].should =~ [story1] }
      end

      describe "WITH two sprints
                WITH two stories
                WITH one story per sprint
                WITH querying for the two sprints" do

        before do
          version2
          story1
          story2.fixed_version_id = version2.id
          story2.save!
        end

        it { Story.backlogs(project, [version.id, version2.id])[version.id].should =~ [story1] }
        it { Story.backlogs(project, [version.id, version2.id])[version2.id].should =~ [story2] }
      end

      describe "WITH two sprints
                WITH two stories
                WITH one story per sprint
                WITH querying one sprints" do

        before do
          version2
          story1

          story2.fixed_version_id = version2.id
          story2.save!
        end

        it { Story.backlogs(project, [version.id])[version.id].should =~ [story1] }
        it { Story.backlogs(project, [version.id])[version2.id].should be_empty }
      end

      describe "WITH two sprints
                WITH two stories
                WITH one story per sprint
                WITH querying for the two sprints
                WITH one sprint beeing in another project" do

        before do
          story1

          other_project = FactoryGirl.create(:project)
          version2.project_id = other_project.id
          story2.fixed_version_id = version2.id
          story2.project = other_project
          story2.save!
        end

        it { Story.backlogs(project, [version.id, version2.id])[version.id].should =~ [story1] }
        it { Story.backlogs(project, [version.id, version2.id])[version2.id].should be_empty }
      end

      describe "WITH one sprint
                WITH the sprint having one story in this project and one story in another project" do
        before(:each) do
          version.sharing = "system"
          version.save!

          another_project = FactoryGirl.create(:project)

          story1
          story2.project = another_project
          story2.save!
        end

        it { Story.backlogs(project, [version.id])[version.id].should =~ [story1] }
      end

      describe "WITH one sprint
                WITH the sprint having two storys
                WITH one beeing the child of the other" do

        before(:each) do
          story1.parent_id = story2.id

          story1.save
        end

        it { Story.backlogs(project, [version.id])[version.id].should =~ [story1, story2] }
      end

      describe "WITH one sprint
                WITH the sprint having one story
                WITH the story having a child task" do

        before(:each) do
          task.parent_id = story1.id

          task.save
        end

        it { Story.backlogs(project, [version.id])[version.id].should =~ [story1] }
      end

      describe "WITH one sprint
                WITH the sprint having one story and one task
                WITH the two having no connection" do

        before(:each) do
          task
          story1
        end

        it { Story.backlogs(project, [version.id])[version.id].should =~ [story1] }
      end
    end
  end

  describe "journals created after adding a subtask to a story" do
    before(:each) do
      @current = FactoryGirl.create(:user, :login => "user1", :mail => "user1@users.com")
      User.stub(:current).and_return(@current)

      @story = FactoryGirl.create(:story, :fixed_version => version,
                                       :project => project,
                                       :status => status1,
                                       :type => type_feature,
                                       :priority => issue_priority)
      @story.project.enabled_module_names += ["backlogs"]

      @work_package ||= FactoryGirl.create(:work_package, :project => project, :status => status1, :type => type_feature, :author => @current)
    end

    it "should create a journal when adding a subtask which has remaining hours set" do
      @work_package.remaining_hours = 15.0
      @work_package.parent_id = @story.id
      @work_package.save!

      @story.journals.last.changed_data[:remaining_hours].should == [nil, 15]
    end

    it "should not create an empty journal when adding a subtask without remaining hours set" do
      @work_package.parent_id  = @story.id
      @work_package.save!

      @story.journals.last.changed_data[:remaining_hours].should be_nil
    end
  end
end
