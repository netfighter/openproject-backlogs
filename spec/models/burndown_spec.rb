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

describe Burndown do
  def set_attribute_journalized(story, attribute, value, day)
    story.reload
    story.send(attribute, value)
    story.save!
    story.current_journal.update_attribute(:created_at, day)
  end

  let(:user) { @user ||= FactoryGirl.create(:user) }
  let(:role) { @role ||= FactoryGirl.create(:role) }
  let(:type_feature) { @type_feature ||= FactoryGirl.create(:type_feature) }
  let(:type_task) { @type_task ||= FactoryGirl.create(:type_task) }
  let(:issue_priority) { @issue_priority ||= FactoryGirl.create(:priority, :is_default => true) }
  let(:version) { @version ||= FactoryGirl.create(:version, :project => project) }
  let(:sprint) { @sprint ||= Sprint.find(version.id) }

  let(:project) do
    unless @project
      @project = FactoryGirl.build(:project)
      @project.members = [FactoryGirl.build(:member, :principal => user,
                                                     :project => @project,
                                                     :roles => [role])]
      @project.versions << version
    end
    @project
  end

  let(:issue_open) { @status1 ||= FactoryGirl.create(:status, :name => "status 1", :is_default => true) }
  let(:issue_closed) { @status2 ||= FactoryGirl.create(:status, :name => "status 2", :is_closed => true) }
  let(:issue_resolved) { @status3 ||= FactoryGirl.create(:status, :name => "status 3", :is_closed => false) }

  before(:each) do
    Rails.cache.clear

    User.stub(:current).and_return(user)

    Setting.plugin_openproject_backlogs = {"points_burn_direction" => "down",
                                           "wiki_template"         => "",
                                           "card_spec"             => "Sattleford VM-5040",
                                           "story_types"           => [type_feature.id.to_s],
                                           "task_type"             => type_task.id.to_s }


    project.save!

    [issue_open, issue_closed, issue_resolved].permutation(2).each do |transition|
      FactoryGirl.create(:workflow,
                         old_status: transition[0],
                         new_status: transition[1],
                         role: role,
                         type_id: type_feature.id)
    end
  end

  describe "Sprint Burndown" do
    describe "WITH the today date fixed to April 4th, 2011 and having a 10 (working days) sprint" do
      before(:each) do
        Time.stub(:now).and_return(Time.utc(2011,"apr",4,20,15,1))
        Date.stub(:today).and_return(Date.civil(2011,04,04))
      end

      describe "WITH having a version in the future" do
        before(:each) do
          version.start_date = Date.today + 1.days
          version.effective_date = Date.today + 6.days
          version.save!
        end

        it "should generate a burndown" do
          sprint.burndown(project).series[:story_points].should be_empty
        end
      end

      describe "WITH having a 10 (working days) sprint and being 5 (working) days into it" do
        before(:each) do
          version.start_date = Date.today - 7.days
          version.effective_date = Date.today + 6.days
          version.save!
        end

        describe "WITH 1 story assigned to the sprint" do
          before(:each) do
            @story = FactoryGirl.build(:story, :subject => "Story 1",
                                               :project => project,
                                               :fixed_version => version,
                                               :type => type_feature,
                                               :status => issue_open,
                                               :priority => issue_priority,
                                               :created_at => Date.today - 20.days,
                                               :updated_at => Date.today - 20.days)
          end

          describe "WITH the story having story_point defined on creation" do
            before(:each) do
              @story.story_points = 9
              @story.save!
              @story.current_journal.update_attribute(:created_at, @story.created_at)
            end

            describe "WITH the story being closed and opened again within the sprint duration" do
              before(:each) do
                set_attribute_journalized @story, :status_id=, issue_closed.id, Time.now - 6.days
                set_attribute_journalized @story, :status_id=, issue_open.id, Time.now - 3.days

                @burndown = Burndown.new(sprint, project)
              end

              it { @burndown.story_points.should eql [9.0, 0.0, 0.0, 0.0, 9.0, 9.0] }
              it { @burndown.story_points.unit.should eql :points }
              it { @burndown.days.should eql(sprint.days()) }
              it { @burndown.max[:hours].should eql 0.0 }
              it { @burndown.max[:points].should eql 9.0 }
              it { @burndown.story_points_ideal.should eql [9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0] }
            end

            describe "WITH the story marked as resolved and consequently 'done'" do
              before(:each) do
                set_attribute_journalized @story, :status_id=, issue_resolved.id, Time.now - 6.days
                set_attribute_journalized @story, :status_id=, issue_open.id, Time.now - 3.days
                project.done_statuses << issue_resolved
                @burndown = Burndown.new(sprint, project)
              end

              it { @story.done?.should eql false }
              it { @burndown.story_points.should eql [9.0, 0.0, 0.0, 0.0, 9.0, 9.0] }
            end
          end
        end

        describe "WITH 10 stories assigned to the sprint" do
          before(:each) do
            @stories = []

            (0..9).each do |i|
              @stories[i] = FactoryGirl.create(:story, :subject => "Story #{i}",
                                               :project => project,
                                               :fixed_version => version,
                                               :type => type_feature,
                                               :status => issue_open,
                                               :priority => issue_priority,
                                               :created_at => Date.today - (20 - i).days,
                                               :updated_at => Date.today - (20 - i).days)
              @stories[i].current_journal.update_attribute(:created_at, @stories[i].created_at)
            end
          end

          describe "WITH each story having story points defined at start" do
            before(:each) do
              @stories.each_with_index do |s, i|
                set_attribute_journalized s, :story_points=, 10, version.start_date - 3.days
              end
            end

            describe "WITH 5 stories having been reduced to 0 story points, one story per day" do
              before(:each) do
                @finished_hours
                (0..4).each do |i|
                  set_attribute_journalized @stories[i], :story_points=, nil, version.start_date + i.days + 1.hour
                end
              end

              describe "THEN" do
                before(:each) do
                  @burndown = Burndown.new(sprint, project)
                end

                it { @burndown.story_points.should eql [90.0, 80.0, 70.0, 60.0, 50.0, 50.0] }
                it { @burndown.story_points.unit.should eql :points }
                it { @burndown.days.should eql(sprint.days()) }
                it { @burndown.max[:hours].should eql 0.0 }
                it { @burndown.max[:points].should eql 90.0 }
                it { @burndown.story_points_ideal.should eql [90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0, 0.0] }
              end
            end
          end

        end
      end
    end
  end
end
