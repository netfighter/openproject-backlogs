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

describe Version do
  it { should have_many :version_settings }

  describe 'rebuild positions' do
    def build_work_package(options = {})
      FactoryGirl.build(:work_package, options.reverse_merge(:fixed_version_id => version.id,
                                                  :priority_id      => priority.id,
                                                  :project_id       => project.id,
                                                  :status_id        => status.id))
    end

    def create_work_package(options = {})
      build_work_package(options).tap { |i| i.save! }
    end

    let(:status)   { FactoryGirl.create(:status)    }
    let(:priority) { FactoryGirl.create(:priority_normal) }
    let(:project)  { FactoryGirl.create(:project, :name => "Project 1", :types => [epic_type, story_type, task_type, other_type])}

    let(:epic_type)  { FactoryGirl.create(:type, :name => 'Epic') }
    let(:story_type) { FactoryGirl.create(:type, :name => 'Story') }
    let(:task_type)  { FactoryGirl.create(:type, :name => 'Task')  }
    let(:other_type) { FactoryGirl.create(:type, :name => 'Other') }

    let(:version) { FactoryGirl.create(:version, :project_id => project.id, :name => 'Version') }

    before do
      # We had problems while writing these specs, that some elements kept
      # creaping around between tests. This should be fast enough to not harm
      # anybody while adding an additional safety net to make sure, that
      # everything runs in isolation.
      WorkPackage.delete_all
      IssuePriority.delete_all
      Status.delete_all
      Project.delete_all
      Type.delete_all
      Version.delete_all

      # Enable and configure backlogs
      project.enabled_module_names = project.enabled_module_names + ["backlogs"]
      Setting.stub(:plugin_openproject_backlogs).and_return({"story_types" => [epic_type.id, story_type.id], "task_type" => task_type.id})

      # Otherwise the type id's from the previous test are still active
      WorkPackage.instance_variable_set(:@backlogs_types, nil)

      project.types = [epic_type, story_type, task_type, other_type]
      version
    end

    it 'moves an work_package to a project where backlogs is disabled while using versions' do
      project2 = FactoryGirl.create(:project, :name => "Project 2", :types => [epic_type, story_type, task_type, other_type])
      project2.enabled_module_names = project2.enabled_module_names - ["backlogs"]
      project2.save!
      project2.reload

      work_package1 = FactoryGirl.create(:work_package, :type_id => task_type.id, :status_id => status.id, :project_id => project.id)
      work_package2 = FactoryGirl.create(:work_package, :parent_id => work_package1.id, :type_id => task_type.id, :status_id => status.id, :project_id => project.id)
      work_package3 = FactoryGirl.create(:work_package, :parent_id => work_package2.id, :type_id => task_type.id, :status_id => status.id, :project_id => project.id)

      work_package1.reload
      work_package1.fixed_version_id = version.id
      work_package1.save!

      work_package1.reload
      work_package2.reload
      work_package3.reload

      work_package3.move_to_project(project2)

      work_package1.reload
      work_package2.reload
      work_package3.reload

      work_package2.move_to_project(project2)

      work_package1.reload
      work_package2.reload
      work_package3.reload

      work_package3.project.should == project2
      work_package2.project.should == project2
      work_package1.project.should == project

      work_package3.fixed_version_id.should be_nil
      work_package2.fixed_version_id.should be_nil
      work_package1.fixed_version_id.should == version.id
    end

    it 'rebuilds postions' do
      e1 = create_work_package(:type_id => epic_type.id)
      s2 = create_work_package(:type_id => story_type.id)
      s3 = create_work_package(:type_id => story_type.id)
      s4 = create_work_package(:type_id => story_type.id)
      s5 = create_work_package(:type_id => story_type.id)
      t3 = create_work_package(:type_id => task_type.id)
      o9 = create_work_package(:type_id => other_type.id)

      [e1, s2, s3, s4, s5].each(&:move_to_bottom)

      # Messing around with positions
      s3.send :assume_not_in_list
      s4.send :assume_not_in_list

      t3.send(:update_attribute_silently, :position, 3)
      o9.send(:update_attribute_silently, :position, 9)

      version.rebuild_positions(project)

      work_packages = version.fixed_issues.find(:all, :conditions => {:project_id => project}, :order => 'COALESCE(position, 0) ASC, id ASC')

      work_packages.map(&:position).should == [nil, nil, 1, 2, 3, 4, 5]
      work_packages.map(&:subject).should == [t3, o9, e1, s2, s5, s3, s4].map(&:subject)

      # Makes sure, that all work_package subjects are uniq, so that the above
      # assertion works as expected
      work_packages.map(&:subject).uniq.size.should == 7
    end
  end
end
