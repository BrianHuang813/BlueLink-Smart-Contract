import React, { useState, useEffect } from 'react';
import { useCurrentAccount } from '@mysten/dapp-kit';
import { Link } from 'react-router-dom';
import { projectService } from '../services/api';
import { Project, DonationReceipt } from '../types';

const DashboardPage: React.FC = () => {
  const [view, setView] = useState<'creator' | 'donor'>('creator');

  const [createdProjects, setCreatedProjects] = useState<Project[]>([]);
  const [donations, setDonations] = useState<DonationReceipt[]>([]);
  
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const currentAccount = useCurrentAccount();

  useEffect(() => {
    const fetchData = async () => {
      if (!currentAccount) {
        setLoading(false);
        return;
      }

      setLoading(true);
      try {
        const [allProjects, donationsData] = await Promise.all([
          projectService.getAllProjects(),
          projectService.getDonationHistory(currentAccount.address)
        ]);
        
        const userProjects = allProjects.filter(p => p.creator === currentAccount.address);
        setCreatedProjects(userProjects);
        setDonations(donationsData);

      } catch (err) {
        setError('無法載入儀表板數據');
        console.error('Error fetching dashboard data:', err);
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [currentAccount]);

  // Loading and Wallet Connection states
  if (!currentAccount) {
    return (
      <div className="max-w-4xl mx-auto text-center bg-yellow-50 border border-yellow-200 rounded-lg p-8">
        <h2 className="text-2xl font-bold text-yellow-800 mb-2">請先連接錢包</h2>
        <p className="text-yellow-700">連接錢包後，您可以在此查看您建立的項目和捐贈記錄。</p>
      </div>
    );
  }

  if (loading) {
    return <div className="text-center text-lg">正在載入儀表板數據...</div>;
  }

  if (error) {
    return <div className="text-center text-red-600 text-lg">{error}</div>;
  }

  return (
    <div className="max-w-6xl mx-auto">
      <h1 className="text-3xl font-bold text-gray-800 mb-6">我的儀表板</h1>

      {/* View Switcher */}
      <div className="mb-6">
        <div className="border-b border-gray-200">
          <nav className="-mb-px flex space-x-6">
            <button
              onClick={() => setView('creator')}
              className={`px-3 py-2 font-medium text-sm rounded-t-md ${view === 'creator' ? 'border-b-2 border-blue-600 text-blue-600' : 'text-gray-500 hover:text-gray-700'}`}>
              我建立的專案 ({createdProjects.length})
            </button>
            <button
              onClick={() => setView('donor')}
              className={`px-3 py-2 font-medium text-sm rounded-t-md ${view === 'donor' ? 'border-b-2 border-blue-600 text-blue-600' : 'text-gray-500 hover:text-gray-700'}`}>
              我的捐贈記錄 ({donations.length})
            </button>
          </nav>
        </div>
      </div>

      {/* Conditional Rendering based on view */}
      {view === 'creator' ? <CreatorDashboard projects={createdProjects} /> : <DonorDashboard donations={donations} />}
    
      <div className="mt-8 pt-6 border-t border-gray-200 text-sm text-gray-600">
        <strong>錢包地址：</strong>
        <div className="font-mono text-xs mt-1 break-all">{currentAccount.address}</div>
      </div>
    </div>
  );
};

// Creator View Component
const CreatorDashboard: React.FC<{ projects: Project[] }> = ({ projects }) => {
  if (projects.length === 0) {
    return (
      <div className="text-center py-16">
        <h3 className="text-xl font-semibold text-gray-700 mb-2">您尚未建立任何項目</h3>
        <Link to="/create" className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 transition-colors inline-block mt-4">
          建立第一個項目
        </Link>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow-lg overflow-hidden">
      <div className="px-6 py-4 border-b"><h2 className="text-xl font-semibold">我建立的專案</h2></div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4">
        {projects.map(p => <CreatorProjectCard key={p.id} project={p} />)}
      </div>
    </div>
  );
};

// Donor View Component (adapted from original page code)
const DonorDashboard: React.FC<{ donations: DonationReceipt[] }> = ({ donations }) => {
  if (donations.length === 0) {
    return (
      <div className="text-center py-16">
        <h3 className="text-xl font-semibold text-gray-700 mb-2">還沒有捐贈記錄</h3>
        <Link to="/" className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 transition-colors inline-block mt-4">
          探索項目
        </Link>
      </div>
    );
  }

  const totalAmount = donations.reduce((sum, d) => sum + (parseFloat(d.amount) / 1000000000), 0);

  return (
    <>
       <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center"><div className="text-3xl mr-4">💝</div><div>
              <div className="text-2xl font-bold text-green-600">{totalAmount.toFixed(2)} SUI</div>
              <div className="text-sm text-gray-600">總捐贈金額</div></div></div>
        </div>
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center"><div className="text-3xl mr-4">🏆</div><div>
              <div className="text-2xl font-bold text-purple-600">{donations.length}</div>
              <div className="text-sm text-gray-600">鏈上數位憑證</div></div></div>
        </div>
      </div>
      <div className="bg-white rounded-lg shadow-lg overflow-hidden">
        <div className="px-6 py-4 border-b"><h2 className="text-xl font-semibold">捐贈記錄</h2></div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">鏈上數位憑證 ID</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">項目 ID</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">金額</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {donations.map((d) => (
                <tr key={d.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4 font-mono text-sm">{d.id.substring(0, 12)}...</td>
                  <td className="px-6 py-4 font-mono text-sm"><Link to={`/project/${d.project_id}`} className="text-blue-600 hover:underline">{d.project_id.substring(0, 12)}...</Link></td>
                  <td className="px-6 py-4 font-bold text-sm text-green-600">{(parseFloat(d.amount) / 1000000000).toFixed(4)} SUI</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
};

// Simple card for the created projects list
const CreatorProjectCard: React.FC<{ project: Project }> = ({ project }) => {
  const fundingGoal = parseFloat(project.funding_goal) / 1000000000;
  const totalRaised = parseFloat(project.total_raised) / 1000000000;
  const progress = fundingGoal > 0 ? (totalRaised / fundingGoal) * 100 : 0;

  return (
    <div className="bg-gray-50 rounded-lg p-4 border border-gray-200">
      <h4 className="font-bold truncate">{project.name}</h4>
      <p className="text-xs text-gray-500 font-mono mb-3">ID: {project.id.substring(0, 12)}...</p>
      <div className="w-full bg-gray-200 rounded-full h-2 mb-1">
        <div className="bg-blue-600 h-2 rounded-full" style={{ width: `${Math.min(progress, 100)}%` }}></div>
      </div>
      <p className="text-xs text-right">{progress.toFixed(1)}% ({totalRaised.toFixed(2)} / {fundingGoal.toFixed(2)} SUI)</p>
      <div className="mt-4 flex space-x-2">
        <Link to={`/project/${project.id}`} className="flex-1 text-center bg-white border border-gray-300 text-sm px-3 py-1 rounded-md hover:bg-gray-100">查看詳情</Link>
        <button disabled className="flex-1 text-center bg-blue-500 text-white text-sm px-3 py-1 rounded-md opacity-50 cursor-not-allowed">提取資金</button>
      </div>
    </div>
  );
}

export default DashboardPage;
